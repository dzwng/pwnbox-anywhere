"""Read-only catalog of this ThinkPad's HTTPS Tailscale Serve websites."""
import json
from pathlib import Path
import re
import subprocess
import threading
import time
from urllib.parse import urlsplit


def discover(serve, public_url, labels=None):
    host = urlsplit(public_url).hostname
    if not host or not re.fullmatch(r"[a-zA-Z0-9.-]+\.ts\.net", host):
        return []
    labels = labels if isinstance(labels, dict) else {}
    sites = {}
    for config in [serve, *serve.get("Foreground", {}).values()]:
        for address, web in config.get("Web", {}).items():
            name, _, port = address.rpartition(":")
            if name.lower() != host.lower() or not port.isdigit() or not 1 <= int(port) <= 65535:
                continue
            if not config.get("TCP", {}).get(port, {}).get("HTTPS"):
                continue
            origin = "https://" + host + (":" + port if port != "443" else "")
            for path, handler in web.get("Handlers", {}).items():
                # Redirects (including the dashboard shortcut) are not hosted websites.
                if not (handler.get("Proxy") or handler.get("Path")) or not path.startswith("/") or path.startswith("//"):
                    continue
                url = origin + path
                if url.rstrip("/") == public_url.rstrip("/"):
                    continue
                record = labels.get(url.rstrip("/"), {})
                if not isinstance(record, dict):
                    record = {}
                sites[url] = {"name": str(record.get("name") or "Website · " + port)[:120],
                              "description": str(record.get("description") or "Hosted on ThinkPad")[:240],
                              "url": url, "public": bool(config.get("AllowFunnel", {}).get(address))}
    return sorted(sites.values(), key=lambda site: (site["name"], site["url"]))


class SitesCatalog:
    def __init__(self, public_url, registry=None, demo=False):
        self.public_url, self.registry, self.demo = public_url, registry, demo
        self.lock = threading.Lock()
        self.due = 0
        self.cached = {"sites": [], "error": "", "checked_at": None}

    def snapshot(self):
        with self.lock:
            if time.monotonic() < self.due:
                return self.cached
            self.due = time.monotonic() + 60
            if self.demo:
                self.cached = {"sites": [{"name": "CRTO tiếng Việt", "description": "Example course website · simulated",
                                         "url": "https://thinkpad.example.ts.net:9443/", "public": False}],
                               "error": "", "checked_at": time.time()}
                return self.cached
            try:
                labels = {}
                if self.registry and Path(self.registry).exists():
                    labels = json.loads(Path(self.registry).read_text(encoding="utf-8"))
                result = subprocess.run(["tailscale", "serve", "status", "--json"],
                                        capture_output=True, text=True, check=True, timeout=5)
                sites = discover(json.loads(result.stdout), self.public_url, labels)
                self.cached = {"sites": sites, "error": "", "checked_at": time.time()}
            except (OSError, ValueError, TypeError, AttributeError, subprocess.SubprocessError):
                self.cached = {"sites": [], "error": "Cannot read hosted websites. Check Tailscale Serve and sites.json on ThinkPad.",
                               "checked_at": None}
            return self.cached
