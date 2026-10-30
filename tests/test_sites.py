"""Keep the pre-existing hosted-site links when updating the dashboard."""
import copy
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "web"))
from sites import discover


class SitesTests(unittest.TestCase):
    def test_catalog_preserves_private_course_and_excludes_dashboard_and_other_hosts(self):
        host = "thinkpad.example.ts.net"
        data = {"TCP": {"443": {"HTTPS": True}, "9443": {"HTTPS": True}},
                "Web": {host + ":443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8787"}}},
                        host + ":9443": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:9090"}}},
                        "other.example.ts.net:9443": {"Handlers": {"/": {"Path": "/srv/other"}}}},
                "AllowFunnel": {}}
        original = copy.deepcopy(data)
        url = "https://" + host + ":9443/"
        result = discover(data, "https://" + host, {url.rstrip("/"): {"name": "Existing course"}})
        self.assertEqual(result, [{"name": "Existing course", "description": "Hosted on ThinkPad", "url": url, "public": False}])
        self.assertEqual(data, original)

    def test_http_redirects_and_foreign_origins_are_not_catalog_entries(self):
        data = {"TCP": {"80": {}, "9443": {"HTTPS": True}}, "Web": {
            "thinkpad.example.ts.net:80": {"Handlers": {"/": {"Proxy": "http://127.0.0.1:8788"}}},
            "thinkpad.example.ts.net:9443": {"Handlers": {"/": {"Redirect": "https://elsewhere.example"}}}}}
        self.assertEqual(discover(data, "https://thinkpad.example.ts.net"), [])
        self.assertEqual(discover(data, "https://outside.example"), [])
