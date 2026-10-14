"""Security, operation lifecycle and demand-driven metrics. No hardware access."""
from concurrent.futures import Future
import http.client
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "web"))
from app import Backend, ControlCenter, Server, Store, password_record
from metrics import LinuxMetrics

TEMP_ROOT = Path(__file__).resolve().parents[1] / ".local/web-tests"
TEMP_ROOT.mkdir(parents=True, exist_ok=True)


class FakeBackend(Backend):
    def __init__(self):
        super().__init__(demo=True)
        self.entered, self.release = threading.Event(), threading.Event()
        self.calls = []

    def operate(self, action, emit):
        self.calls.append(action)
        self.entered.set()
        emit("Waiting for target")
        self.release.wait(3)
        return 0


class HTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.password = password_record("test-password-123")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=TEMP_ROOT)
        self.backend = FakeBackend()
        self.center = ControlCenter(Path(self.tmp.name), self.backend)
        self.server = Server(("127.0.0.1", 0), self.center,
                             {"public_url": "http://127.0.0.1", "password": self.password})
        self.origin = f"http://127.0.0.1:{self.server.server_port}"
        self.server.config["public_url"] = self.origin
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.cookie = self.csrf = None

    def tearDown(self):
        self.backend.release.set()
        self.center.stop.set()
        self.center.thread.join(2)
        self.server.shutdown()
        self.server.server_close()
        self.center.pool.shutdown(wait=True)
        deadline = time.monotonic() + 3
        while self.center.active() and time.monotonic() < deadline:
            time.sleep(.01)
        self.center.store.db.close()
        self.tmp.cleanup()

    def request(self, path, data=None, headers=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=5)
        merged = {"Origin": self.origin, "Content-Type": "application/json"}
        if self.cookie:
            merged["Cookie"] = self.cookie
        if self.csrf:
            merged["X-CSRF-Token"] = self.csrf
        merged.update(headers or {})
        connection.request("GET" if data is None else "POST", path, None if data is None else json.dumps(data), merged)
        response = connection.getresponse()
        body = response.read()
        output = (response.status, dict(response.getheaders()), json.loads(body) if "application/json" in response.getheader("Content-Type", "") else body)
        connection.close()
        return output

    def login(self):
        status, headers, result = self.request("/api/login", {"password": "test-password-123"})
        self.assertEqual(status, 200)
        self.cookie = headers["Set-Cookie"].split(";")[0]
        self.csrf = result["csrf"]
        self.assertIn("HttpOnly", headers["Set-Cookie"])
        self.assertIn("SameSite=Strict", headers["Set-Cookie"])

    def test_auth_and_static_file_allowlist(self):
        self.assertEqual(self.request("/api/snapshot")[0], 401)
        self.assertEqual(self.request("/")[0], 200)
        self.assertEqual(self.request("/thinkpad.svg")[0], 200)
        self.assertEqual(self.request("/desktop.svg")[0], 200)
        self.login()
        self.assertEqual(self.request("/api/snapshot")[0], 200)
        self.assertEqual(self.request("/../../config/pwnbox.conf")[0], 404)
        self.assertEqual(self.request("/web/app.py")[0], 404)
        self.assertEqual(self.request("/api/snapshot", headers={"Host":"evil.example"})[0], 403)

    def test_csrf_origin_confirmation_and_command_allowlist(self):
        self.login()
        data = {"action":"kali", "confirmed":True, "request_id":"request-1234567890"}
        self.assertEqual(self.request("/api/actions", data, {"Origin":"https://evil.example"})[0], 403)
        self.assertEqual(self.request("/api/actions", data, {"X-CSRF-Token":"bad"})[0], 403)
        self.assertEqual(self.request("/api/actions", dict(data, confirmed=False))[0], 400)
        self.assertEqual(self.request("/api/actions", dict(data, action="kali; shutdown"))[0], 400)
        self.assertEqual(self.request("/api/actions", dict(data, action=["kali"]))[0], 400)
        self.assertEqual(self.backend.calls, [])

    def test_job_survives_reload_is_idempotent_and_rejects_overlap(self):
        self.login()
        data = {"action":"kali", "confirmed":True, "request_id":"request-1234567890"}
        status, _, result = self.request("/api/actions", data)
        self.assertEqual(status, 202)
        self.assertTrue(self.backend.entered.wait(1))
        self.assertEqual(self.request("/api/actions", data)[2]["job_id"], result["job_id"])
        self.assertEqual(self.request("/api/actions", dict(data, request_id="request-1234567891"))[0], 409)
        self.assertEqual(self.request("/api/actions", dict(data, action="windows"))[0], 409)
        jobs = self.request("/api/snapshot")[2]["jobs"]
        self.assertEqual(jobs[0]["status"], "running")
        self.assertEqual(self.backend.calls, ["kali"])
        self.backend.release.set()
        for _ in range(100):
            if not self.center.active():
                break
            time.sleep(.01)
        self.assertEqual(self.center.state["state"], "KALI")
        self.assertEqual(self.request("/api/snapshot")[2]["jobs"][0]["status"], "success")
        self.assertEqual(self.request("/api/actions", data)[0], 202)
        self.assertEqual(self.backend.calls, ["kali"])

    def test_logout_revokes_session(self):
        self.login()
        self.assertEqual(self.request("/api/logout", {})[0], 200)
        self.assertEqual(self.request("/api/snapshot")[0], 401)

    def test_bootnext_preserves_running_os_and_reboot_records_target(self):
        self.login()
        self.backend.release.set()
        for i, (action, expected) in enumerate([
            ("bootnext-kali", "WINDOWS"), ("bootnext-windows", "WINDOWS"),
            ("reboot-kali", "KALI"), ("reboot-windows", "WINDOWS"),
        ]):
            with self.subTest(action=action):
                data = {"action": action, "confirmed": True, "request_id": f"request-new-action-{i:08}"}
                self.assertEqual(self.request("/api/actions", data)[0], 202)
                for _ in range(100):
                    if not self.center.active():
                        break
                    time.sleep(.01)
                result = self.request("/api/snapshot")[2]
                self.assertEqual(result["status"]["state"], expected)
                self.assertEqual(result["jobs"][0]["action"], action)
                self.assertEqual(result["jobs"][0]["status"], "success")
                self.assertEqual(self.request("/api/actions", data)[0], 202)
        self.assertEqual(self.backend.calls, ["bootnext-kali", "bootnext-windows", "reboot-kali", "reboot-windows"])

    def test_new_actions_require_confirmation_csrf_and_exact_allowlist(self):
        self.login()
        for action in ("bootnext-kali", "reboot-windows"):
            data = {"action": action, "confirmed": True, "request_id": "request-new-security-123"}
            self.assertEqual(self.request("/api/actions", dict(data, confirmed=False))[0], 400)
            self.assertEqual(self.request("/api/actions", data, {"X-CSRF-Token": "bad"})[0], 403)
            self.assertEqual(self.request("/api/actions", dict(data, action=action + "; off"))[0], 400)
        self.assertEqual(self.backend.calls, [])

    def test_failed_operation_never_reports_target_os_ready(self):
        self.login()
        with patch.object(self.backend, "operate", return_value=5):
            self.assertEqual(self.request("/api/actions", {"action":"kali", "confirmed":True,
                "request_id":"request-failure-123456"})[0], 202)
            for _ in range(100):
                if not self.center.active():
                    break
                time.sleep(.01)
            self.assertEqual(self.center.store.jobs()[0]["status"], "failed")
            self.assertNotEqual(self.center.state["state"], "KALI")

    def test_login_rate_limit(self):
        for _ in range(5):
            self.assertEqual(self.request("/api/login", {"password":"wrong"})[0], 401)
        self.assertEqual(self.request("/api/login", {"password":"wrong"})[0], 429)

    def test_firmware_failure_retains_evidence_and_is_not_success(self):
        self.login()
        def failed_audit(action, emit):
            emit("Firmware BootOrder (before, WINDOWS): Windows,Kali; Windows first: true")
            emit("Firmware BootOrder (after, KALI): Kali,Windows; Windows first: false")
            emit("OS reached, but Windows is not first in firmware BootOrder.")
            return 5
        with patch.object(self.backend, "operate", side_effect=failed_audit):
            self.assertEqual(self.request("/api/actions", {"action": "kali", "confirmed": True,
                "request_id": "request-firmware-failure-123456"})[0], 202)
            for _ in range(100):
                if not self.center.active():
                    break
                time.sleep(.01)
            job = self.request("/api/snapshot")[2]["jobs"][0]
            self.assertEqual(job["status"], "failed")
            self.assertEqual(job["code"], 5)
            self.assertIn("Windows first: true", job["events"][0]["message"])
            self.assertIn("Windows first: false", job["events"][1]["message"])

    def test_body_size_and_content_type(self):
        self.assertEqual(self.request("/api/login", {"password":"x"*5000})[0], 413)
        self.assertEqual(self.request("/api/login", {}, {"Content-Type":"text/plain"})[0], 415)

    def test_diagnostics_do_not_operate_or_duplicate(self):
        self.login()
        self.assertEqual(self.request("/api/diagnose", {})[0], 202)
        # Collect completed read-only result, then enforce throttling.
        time.sleep(.05)
        self.center.tick()
        self.assertEqual(self.request("/api/diagnose", {})[0], 409)
        self.assertEqual(self.backend.calls, [])


class LifecycleTests(unittest.TestCase):
    def test_demo_bootnext_does_not_change_os_and_reboot_can_stay_in_kali(self):
        backend = Backend(demo=True)
        events = []
        self.assertEqual(backend.operate("bootnext-kali", events.append), 0)
        self.assertEqual(backend.status()["state"], "WINDOWS")
        with patch("app.time.sleep"):
            self.assertEqual(backend.operate("reboot-kali", events.append), 0)
            self.assertEqual(backend.status()["state"], "KALI")
            self.assertEqual(backend.operate("reboot-kali", events.append), 0)
            self.assertEqual(backend.status()["state"], "KALI")
        backend.demo_state = "OFF"
        self.assertEqual(backend.operate("bootnext-kali", events.append), 3)
        self.assertEqual(backend.operate("reboot-kali", events.append), 3)
        self.assertEqual(backend.status()["state"], "OFF")

    def test_restart_interrupts_without_replaying_and_retention_is_bounded(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as directory:
            path = Path(directory) / "state.db"
            store = Store(path)
            job, _ = store.submit("off", "request-1234567890")
            for _ in range(150):
                store.event(job, "x"*800)
            self.assertEqual(len(store.jobs()[0]["events"]), 120)
            self.assertEqual(len(store.jobs()[0]["events"][0]["message"]), 500)
            store.db.close()
            store = Store(path)
            self.assertEqual(store.jobs()[0]["status"], "interrupted")
            self.assertEqual(store.submit("off", "request-1234567890"), (job, False))
            for i in range(205):
                job, _ = store.submit("windows", f"request-{i:016}")
                store.finish(job, 0)
            self.assertEqual(len(store.jobs()), 200)
            store.db.close()

    def test_demand_sampling_no_overlap_and_late_old_os_result_ignored(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as directory:
            backend = FakeBackend()
            center = ControlCenter(Path(directory), backend)
            center.stop.set()
            center.thread.join(2)
            with patch.object(backend, "status") as status, patch.object(backend, "metrics") as metrics:
                center.tick()
                status.assert_not_called()
                metrics.assert_not_called()
            center.state = {"state":"WINDOWS", "checked_at":time.time()}
            center.view_until = time.monotonic()+12
            center.due["status"] = time.monotonic()+30
            future = Future()
            center.futures["metrics"] = future, center.epoch
            with patch.object(backend, "metrics") as metrics:
                center.tick()
                center.tick()
                metrics.assert_not_called()
            center.epoch += 1
            center.state = {"state":"KALI", "checked_at":time.time()}
            future.set_result({"os":"WINDOWS", "cpu_percent":99})
            center.view_until = 0
            center.tick()
            self.assertEqual(center.desktop, {})
            center.pool.shutdown(wait=True)
            center.store.db.close()

    def test_metrics_payload_requires_live_os_marker(self):
        backend = Backend()
        with patch("app.subprocess.run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = '{"os":"WINDOWS","cpu_percent":14}'
            with self.assertRaisesRegex(RuntimeError, "OS"):
                backend.metrics("KALI", False)
            run.return_value.stdout = '{"os":"KALI","cpu_percent":14,"sampled_at":1}'
            self.assertGreater(backend.metrics("KALI", False)["sampled_at"], 1)


class MetricsTests(unittest.TestCase):
    def test_diagnostics_distinguish_inactive_os_from_unverified_desktop(self):
        data = {"lan_healthy": True, "windows_ssh_verified": True, "kali_ssh_verified": False,
                "windows_detail": "", "kali_detail": "Host key verification failed."}
        with patch("app.subprocess.run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = json.dumps(data)
            result = Backend().diagnostics()["output"]
            self.assertIn("desktop verified as WINDOWS", result)
            self.assertNotIn("Host key verification failed", result)
            data["windows_ssh_verified"] = False
            run.return_value.stdout = json.dumps(data)
            result = Backend().diagnostics()["output"]
            self.assertIn("Host key verification failed", result)
            self.assertNotIn("Not running; desktop verified", result)

    def test_linux_cpu_available_memory_battery_and_amd_vram(self):
        with tempfile.TemporaryDirectory(dir=TEMP_ROOT) as directory:
            root = Path(directory)
            proc, sysfs = root / "proc", root / "sys"
            proc.mkdir()
            (proc / "stat").write_text("cpu 100 0 100 800 0 0 0 0 20 0\n")
            (proc / "meminfo").write_text("MemTotal: 8192000 kB\nMemAvailable: 4096000 kB\nMemFree: 100 kB\n")
            (proc / "uptime").write_text("12345 54321\n")
            bat = sysfs / "class/power_supply/BAT0"
            bat.mkdir(parents=True)
            for name, value in {"capacity":"68", "status":"Not charging", "energy_full":"40", "energy_full_design":"50"}.items():
                (bat / name).write_text(value)
            (bat / "charge_control_start_threshold").write_text("60")
            (bat / "charge_control_end_threshold").write_text("80")
            ac = sysfs / "class/power_supply/AC"
            ac.mkdir()
            (ac / "type").write_text("Mains")
            (ac / "online").write_text("1")
            gpu = sysfs / "class/drm/card1/device"
            gpu.mkdir(parents=True)
            for name, value in {"vendor":"0x1002", "mem_info_vram_total":str(16*1024**3), "mem_info_vram_used":str(2*1024**3), "gpu_busy_percent":"12"}.items():
                (gpu / name).write_text(value)
            collector = LinuxMetrics(proc, sysfs, directory)
            first = collector.sample()
            self.assertIsNone(first["cpu_percent"])
            self.assertEqual(first["ram_used"], 4096000*1024)
            self.assertEqual(first["battery_health"], 80)
            self.assertIs(first["ac_online"], True)
            self.assertEqual(first["battery_status"], "Not charging")
            self.assertEqual(first["charge_start_threshold"], 60)
            self.assertEqual(first["charge_stop_threshold"], 80)
            (ac / "online").write_text("0")
            collector.next_health = 0
            self.assertIs(collector.sample()["ac_online"], False)
            (proc / "stat").write_text("cpu 125 0 125 950 0 0 0 0 20 0\n")
            self.assertEqual(collector.sample()["cpu_percent"], 25)
            self.assertEqual(collector.gpu()["vram_total"], 16*1024**3)
            self.assertEqual(collector.gpu()["gpu_percent"], 12)
            (gpu / "gpu_busy_percent").unlink()
            self.assertIsNone(collector.gpu()["gpu_percent"])
            with patch("metrics.shutil.disk_usage") as disk:
                collector.sample()
                disk.assert_not_called()

    def test_missing_sensors_do_not_become_zero(self):
        collector = LinuxMetrics("missing-proc", "missing-sys", "missing-disk")
        self.assertIsNone(collector.sample()["cpu_percent"])
        self.assertIsNone(collector.sample()["temperature"])
        self.assertIsNone(collector.sample()["ac_online"])
        self.assertIsNone(collector.gpu()["vram_used"])


if __name__ == "__main__":
    unittest.main()
