"""Shortcut routing and Serve collision checks; no Tailscale/device mutations."""
import copy
import http.client
import json
from pathlib import Path
import sys
import threading
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "web"))
from app import Server, ShortcutHandler
from shortcuts import plan

NAME = "pwnbox-relay.tail47b2d7.ts.net"
URL = "https://" + NAME
NODE = {"Self": {"DNSName": NAME + ".", "TailscaleIPs": ["100.111.252.9", "fd7a:115c:a1e0::1"]}}
SERVE = {"TCP": {"443": {"HTTPS": True}},
         "Web": {NAME + ":443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8787"}}}}}


class ShortcutTests(unittest.TestCase):
    def test_installer_adds_only_tcp_entry_point_and_rerun_is_noop(self):
        root = Path(__file__).resolve().parents[1]
        installer = (root / "setup/enable-web-shortcuts.sh").read_text()
        source = installer.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        serve = copy.deepcopy(SERVE)
        def status(args, **kwargs):
            if args == ['tailscale', 'status', '--json']:
                return json.dumps(NODE).encode()
            self.assertEqual(args, ['tailscale', 'serve', 'status', '--json'])
            return json.dumps(serve).encode()
        def install(args, **kwargs):
            self.assertEqual(args, ['sudo', 'tailscale', 'serve', '--bg', '--tcp=80', 'tcp://127.0.0.1:8788'])
            serve['TCP']['80'] = {'TCPForward': '127.0.0.1:8788'}
        temporary = root / '.local/web-tests'
        temporary.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temporary) as directory:
            config = Path(directory) / 'web.json'
            config.write_text(json.dumps({'public_url': URL}))
            with patch('sys.argv', ['installer', str(root), str(config)]), \
                 patch('subprocess.check_output', side_effect=status), \
                 patch('subprocess.run', side_effect=install) as run, \
                 patch('urllib.request.build_opener') as opener, patch('builtins.print'):
                opener.return_value.open.side_effect = urllib.error.HTTPError('', 302, '', {'Location': URL + '/'}, None)
                exec(compile(source, 'shortcut-installer', 'exec'), {})
                run.assert_called_once()
                self.assertEqual(serve['Web'], SERVE['Web'])
                self.assertEqual(serve['TCP']['443'], SERVE['TCP']['443'])
                run.reset_mock()
                exec(compile(source, 'shortcut-installer', 'exec'), {})
                run.assert_not_called()

    def test_redirect_is_fixed_and_has_no_login_or_api(self):
        # No backend/center exists: this listener cannot read metrics or operate devices.
        server = Server(("127.0.0.1", 0), None, {"public_url": URL}, ShortcutHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for method, path in (("GET", "/"), ("GET", "/api/snapshot"),
                                 ("GET", "//evil.example/?next=https://evil.example"), ("HEAD", "/"),
                                 ("POST", "/api/login"), ("POST", "/api/actions")):
                with self.subTest(method=method, path=path):
                    conn = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
                    conn.request(method, path, headers={"Host": "100.111.252.9:80", "Cookie": "pwnbox_session=test"})
                    response = conn.getresponse()
                    self.assertEqual(response.read(), b"")
                    self.assertIsNone(response.getheader("Set-Cookie"))
                    if method in ("GET", "HEAD"):
                        self.assertEqual(response.status, 302)
                        self.assertEqual(response.getheader("Location"), URL + "/")
                        self.assertEqual(response.getheader("Cache-Control"), "no-store")
                    else:
                        self.assertEqual(response.status, 405)
                        self.assertIsNone(response.getheader("Location"))
                    conn.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(2)

    def test_new_shortcuts_and_idempotent_plan_preserve_routes(self):
        serve = copy.deepcopy(SERVE)
        before = copy.deepcopy(serve)
        result = plan(NODE, serve, URL)
        self.assertFalse(result["already"])
        self.assertEqual(result["urls"], ["http://pwnbox-relay", "http://100.111.252.9:80"])
        self.assertEqual(serve, before)
        serve["TCP"]["80"] = {"TCPForward": "127.0.0.1:8788"}
        self.assertTrue(plan(NODE, serve, URL)["already"])

    def test_existing_port_and_funnel_are_not_replaced(self):
        for collision in ({"HTTP": True}, {"TCPForward": "localhost:22"}):
            serve = copy.deepcopy(SERVE)
            serve["TCP"]["80"] = collision
            with self.assertRaisesRegex(ValueError, "port 80"):
                plan(NODE, serve, URL)
        serve = copy.deepcopy(SERVE)
        serve["Web"][NAME + ":80"] = {"Handlers": {"/other": {"Text": "other service"}}}
        with self.assertRaisesRegex(ValueError, "port 80"):
            plan(NODE, serve, URL)
        serve = copy.deepcopy(SERVE)
        serve["Foreground"] = {"session": {"TCP": {"80": {"HTTP": True}}}}
        with self.assertRaisesRegex(ValueError, "foreground"):
            plan(NODE, serve, URL)
        serve = copy.deepcopy(SERVE)
        serve["AllowFunnel"] = {NAME + ":443": True}
        with self.assertRaisesRegex(ValueError, "Funnel"):
            plan(NODE, serve, URL)
        serve = copy.deepcopy(SERVE)
        serve["Foreground"] = {"session": {"AllowFunnel": {NAME + ":443": True}}}
        with self.assertRaisesRegex(ValueError, "Funnel"):
            plan(NODE, serve, URL)

    def test_verify_real_https_route_and_node_before_changes(self):
        with self.assertRaisesRegex(ValueError, "URL"):
            plan(NODE, SERVE, "https://other.tail47b2d7.ts.net")
        with self.assertRaisesRegex(ValueError, "HTTPS Serve"):
            plan(NODE, {}, URL)
        node = copy.deepcopy(NODE)
        node["Self"]["TailscaleIPs"] = ["192.168.1.201"]
        with self.assertRaisesRegex(ValueError, "IPv4"):
            plan(node, SERVE, URL)


if __name__ == "__main__":
    unittest.main()
