"""Pwnbox Control Center: loopback HTTP behind Tailscale Serve, stdlib only."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import copy
import getpass
import hashlib
import hmac
from http import cookies
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import re
import secrets
import signal
import sqlite3
import subprocess
import threading
import time
from urllib.parse import urlsplit

from metrics import LinuxMetrics

ROOT = Path(__file__).resolve().parent.parent
STATIC = ROOT / "web" / "static"
STATES = {"WINDOWS", "KALI", "UNKNOWN", "OFF", "TRANSITIONING"}
ACTIONS = {"windows", "kali", "off", "bootnext-windows", "bootnext-kali", "reboot-windows", "reboot-kali"}
SESSION_TTL = 7 * 86400


def password_record(password):
    salt = secrets.token_hex(16)
    return {"salt": salt, "hash": hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), 600000).hex()}


def password_matches(password, record):
    actual = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(record["salt"]), 600000).hex()
    return hmac.compare_digest(actual, record["hash"])


class Store:
    def __init__(self, path):
        self.lock = threading.RLock()
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        with self.transaction() as db:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS jobs (
                  id TEXT PRIMARY KEY, request_id TEXT UNIQUE, action TEXT, status TEXT,
                  started REAL, finished REAL, events TEXT, code INTEGER);
                CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, csrf TEXT, expires REAL);
                CREATE INDEX IF NOT EXISTS jobs_time ON jobs(started);
            """)
            # A crashed/restarted server must never automatically replay a power command.
            db.execute("UPDATE jobs SET status='interrupted', finished=?, code=3 WHERE status='running'", (time.time(),))

    @contextmanager
    def transaction(self):
        with self.lock:
            try:
                yield self.db
                self.db.commit()
            except Exception:
                self.db.rollback()
                raise

    def jobs(self):
        with self.lock:
            rows = self.db.execute("SELECT * FROM jobs ORDER BY started DESC LIMIT 200").fetchall()
            return [dict(row, events=json.loads(row["events"])) for row in rows]

    def submit(self, action, request_id):
        with self.transaction() as db:
            previous = db.execute("SELECT id,action FROM jobs WHERE request_id=?", (request_id,)).fetchone()
            if previous:
                if previous["action"] != action:
                    raise ValueError("This request ID has already been used for another action.")
                return previous["id"], False
            if db.execute("SELECT 1 FROM jobs WHERE status='running'").fetchone():
                raise ValueError("An operation is already running. Please wait for its result.")
            job_id = secrets.token_hex(12)
            db.execute("INSERT INTO jobs VALUES (?,?,?,'running',?,NULL,'[]',NULL)",
                       (job_id, request_id, action, time.time()))
            db.execute("DELETE FROM jobs WHERE id NOT IN (SELECT id FROM jobs ORDER BY started DESC LIMIT 200)")
            return job_id, True

    def event(self, job_id, message):
        message = re.sub(r"[\x00-\x1f\x7f]", "", message)[:500]
        if not message:
            return
        with self.transaction() as db:
            row = db.execute("SELECT events FROM jobs WHERE id=?", (job_id,)).fetchone()
            events = json.loads(row[0])[-119:] + [{"time": time.time(), "message": message}]
            db.execute("UPDATE jobs SET events=? WHERE id=?", (json.dumps(events), job_id))

    def finish(self, job_id, code):
        with self.transaction() as db:
            db.execute("UPDATE jobs SET status=?,code=?,finished=? WHERE id=?",
                       ("success" if code == 0 else "failed", code, time.time(), job_id))

    def session(self, token):
        with self.transaction() as db:
            db.execute("DELETE FROM sessions WHERE expires<?", (time.time(),))
            return db.execute("SELECT csrf FROM sessions WHERE token=?", (hashlib.sha256(token.encode()).hexdigest(),)).fetchone()

    def login(self):
        token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(32)
        with self.transaction() as db:
            db.execute("DELETE FROM sessions WHERE expires<?", (time.time(),))
            db.execute("INSERT INTO sessions VALUES (?,?,?)", (hashlib.sha256(token.encode()).hexdigest(), csrf, time.time() + SESSION_TTL))
        return token, csrf

    def logout(self, token):
        with self.transaction() as db:
            db.execute("DELETE FROM sessions WHERE token=?", (hashlib.sha256(token.encode()).hexdigest(),))


class Backend:
    def __init__(self, demo=False):
        self.demo = demo
        self.demo_state = "WINDOWS"

    def status(self):
        if self.demo:
            return {"state": self.demo_state, "checked_at": time.time(), "detail": "Simulated data."}
        result = subprocess.run([str(ROOT / "bin" / "pwnbox"), "status"], capture_output=True, text=True, timeout=40)
        state = result.stdout.strip()
        return {"state": state if state in STATES else "UNKNOWN", "checked_at": time.time(),
                "detail": result.stderr.strip()[-500:] if state == "UNKNOWN" or state not in STATES else ""}

    def metrics(self, state, disk):
        if self.demo:
            t = time.time()
            return {"os": state, "sampled_at": t, "cpu_percent": round(12 + 8 * math.sin(t / 10), 1),
                    "ram_used": 9.4 * 1024 ** 3, "ram_total": 32 * 1024 ** 3,
                    "disk_used": 372 * 1024 ** 3, "disk_total": 931 * 1024 ** 3,
                    "disk_mount": "C:" if state == "WINDOWS" else "/", "disk_sampled_at": t,
                    "gpu_percent": round(9 + 6 * math.sin(t / 8), 1),
                    "vram_used": 2.3 * 1024 ** 3, "vram_total": 16 * 1024 ** 3}
        result = subprocess.run([str(ROOT / "bin" / "pwnbox-metrics"), state, "disk" if disk else "fast"],
                                capture_output=True, text=True, timeout=14)
        if result.returncode:
            raise RuntimeError("Cannot read metrics. Check SSH and the metrics helper on the running OS.")
        data = json.loads(result.stdout)
        if not isinstance(data, dict) or data.get("os") != state:
            raise RuntimeError("The metrics endpoint did not verify the expected OS.")
        # Never trust the remote system's clock for freshness.
        data["sampled_at"] = time.time()
        if "disk_total" in data:
            data["disk_sampled_at"] = data["sampled_at"]
        for key in ("cpu_percent", "ram_used", "ram_total", "disk_used", "disk_total", "gpu_percent", "vram_used", "vram_total"):
            value = data.get(key)
            if value is not None and (not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0):
                data[key] = None
        return data

    def diagnostics(self):
        if self.demo:
            detail = ("Desktop powered off (simulated). Neither OS is running." if self.demo_state == "OFF" else
                      f"{self.demo_state} verified over SSH (simulated). The other OS is not running.")
            return {"time": time.time(), "output": "Demo: controller ready. " + detail}
        result = subprocess.run([str(ROOT / "bin" / "pwnbox-diagnostics")], capture_output=True, text=True, timeout=40)
        if result.returncode:
            return {"time": time.time(), "output": "Diagnostics unavailable. Check the controller configuration and dependencies."}
        data = json.loads(result.stdout)
        lines = ["LAN gateway: " + ("Reachable" if data['lan_healthy'] else "Unreachable / not configured")]
        for name in ('windows', 'kali'):
            other = 'kali' if name == 'windows' else 'windows'
            if data[other + '_ssh_verified'] and not data[name + '_ssh_verified']:
                lines.append(name.upper() + ' SSH: Not running; desktop verified as ' + other.upper() + '.')
                continue
            lines.append(name.upper() + " SSH: " + ("OS verified" if data[name + '_ssh_verified'] else "Not verified"))
            if data[name + '_detail']:
                lines.append("  " + data[name + '_detail'].strip())
        return {"time": time.time(), "output": "\n".join(lines)}

    def operate(self, action, emit):
        if action not in ACTIONS:
            raise ValueError("Unsupported controller action.")
        if self.demo:
            emit("[pwnbox] Desktop: " + self.demo_state)
            if action.startswith(("bootnext-", "reboot-")):
                if self.demo_state not in ("WINDOWS", "KALI"):
                    emit("[pwnbox] Cannot identify a running OS; refusing BootNext/reboot.")
                    return 3
                target = action.split("-", 1)[1].upper()
                emit("[pwnbox] BootNext set to " + target + " (demo).")
                if action.startswith("bootnext-"):
                    return 0
                emit("[pwnbox] Requesting clean reboot...")
                time.sleep(2)
                self.demo_state = target
                emit("[pwnbox] " + target + " verified after reboot (demo).")
                return 0
            emit("[pwnbox] Requesting clean shutdown..." if action == "off" else "[pwnbox] Sending Wake-on-LAN / one-time boot request...")
            time.sleep(2)
            emit("[pwnbox] Waiting for " + ("OFF" if action == "off" else action.upper()) + "...")
            time.sleep(2)
            self.demo_state = "OFF" if action == "off" else action.upper()
            emit("[pwnbox] " + self.demo_state + " verified (demo).")
            return 0
        proc = subprocess.Popen([str(ROOT / "bin" / "pwnbox"), action], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, start_new_session=True)
        def read():
            for line in iter(lambda: proc.stdout.readline(2048), ""):
                emit(line.strip())
        reader = threading.Thread(target=read, daemon=True)
        reader.start()
        try:
            code = proc.wait(timeout=1200)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()
            emit("Operation timed out; inspect current state before retrying.")
            code = 4
        reader.join(timeout=2)
        proc.stdout.close()
        return code


class ControlCenter:
    def __init__(self, state_dir, backend):
        state_dir.mkdir(parents=True, exist_ok=True)
        self.store = Store(state_dir / "web.sqlite3")
        self.backend = backend
        self.lock = threading.RLock()
        self.local = LinuxMetrics()
        self.pool = ThreadPoolExecutor(max_workers=3)
        self.stop = threading.Event()
        self.view_until = 0
        self.epoch = 0
        self.state = {"state": "UNKNOWN", "checked_at": None, "detail": "Waiting for a status check."}
        self.thinkpad = {}
        self.desktop = {}
        self.diagnostic = {"time": None, "output": "Run a connectivity check to see results."}
        self.futures = {}
        self.due = {"local": 0, "status": 0, "metrics": 0, "disk": 0}
        self.diagnostic_due = 0
        self.thread = threading.Thread(target=self.loop, daemon=True)
        self.thread.start()

    def active(self):
        return next((j for j in self.store.jobs() if j["status"] == "running"), None)

    def snapshot(self):
        with self.lock:
            self.view_until = time.monotonic() + 12
            return copy.deepcopy({"demo": self.backend.demo, "status": self.state, "thinkpad": self.thinkpad,
                                  "desktop": self.desktop, "jobs": self.store.jobs(), "diagnostic": self.diagnostic,
                                  "diagnostic_running": "diagnostic" in self.futures})

    def tick(self):
        now = time.monotonic()
        with self.lock:
            for kind, (future, epoch) in list(self.futures.items()):
                if not future.done():
                    continue
                del self.futures[kind]
                try:
                    data = future.result()
                    if epoch != self.epoch:
                        continue
                    if kind == "status":
                        if self.state["state"] != data["state"]:
                            self.desktop = {}
                            self.due["disk"] = self.due["metrics"] = 0
                        self.state = data
                    elif kind == "metrics":
                        if data.get("os") == self.state["state"]:
                            self.desktop.update(data, error=None)
                    else:
                        self.diagnostic = data
                except Exception:
                    if epoch == self.epoch:
                        if kind == "metrics":
                            self.desktop["error"] = "Cannot read metrics. Check SSH and the metrics helper; previous data may be stale."
                        elif kind == "status":
                            self.state = {"state": "UNKNOWN", "checked_at": time.time(), "detail": "OS check failed. See Diagnostics."}
                            self.desktop = {}
                        else:
                            self.diagnostic = {"time": time.time(), "output": "Diagnostics failed or timed out."}
            if now > self.view_until:
                return
            if now >= self.due["local"]:
                self.thinkpad = self.local.sample()
                if self.backend.demo:
                    self.thinkpad.update(cpu_percent=round(3 + 2 * math.sin(time.time() / 9), 1),
                        ram_used=1.2 * 1024 ** 3, ram_total=8 * 1024 ** 3, disk_used=58 * 1024 ** 3,
                        disk_total=237 * 1024 ** 3, temperature=43, battery_percent=68,
                        battery_health=87, battery_status="Not charging", ac_online=True,
                        charge_start_threshold=60, charge_stop_threshold=80, uptime=342000)
                self.due["local"] = now + 5
            if self.active():
                return
            if now >= self.due["status"] and "status" not in self.futures:
                self.futures["status"] = self.pool.submit(self.backend.status), self.epoch
                self.due["status"] = now + 30
            state = self.state["state"]
            if state in ("WINDOWS", "KALI") and now >= self.due["metrics"] and "metrics" not in self.futures:
                disk = now >= self.due["disk"]
                self.futures["metrics"] = self.pool.submit(self.backend.metrics, state, disk), self.epoch
                self.due["metrics"] = now + 5
                if disk:
                    self.due["disk"] = now + 60

    def loop(self):
        while not self.stop.wait(0.5):
            self.tick()

    def submit(self, action, request_id):
        with self.lock:
            job_id, new = self.store.submit(action, request_id)
            if new:
                self.epoch += 1
                if not action.startswith("bootnext-"):
                    self.state = {"state": "TRANSITIONING", "checked_at": time.time(), "detail": "Operation in progress."}
                    self.desktop = {}
                threading.Thread(target=self.run_job, args=(job_id, action), daemon=True).start()
            return job_id

    def run_job(self, job_id, action):
        code = 5
        verified_state = None
        try:
            code = self.backend.operate(action, lambda message: self.store.event(job_id, message))
            if code == 0 and action.startswith("bootnext-"):
                verified_state = self.backend.status()
        except Exception:
            self.store.event(job_id, "Cannot run the controller command. Check the service log on the ThinkPad.")
        with self.lock:
            # CLI success includes live verification; no optimistic UI success.
            target = action.removeprefix("reboot-").upper()
            self.state = verified_state or {"state": ("OFF" if action == "off" else target) if code == 0 and not action.startswith("bootnext-") else "UNKNOWN",
                          "checked_at": time.time(), "detail": "" if code == 0 else "The requested state has not been verified."}
            self.epoch += 1
            self.due["status"] = time.monotonic() + 30 if code == 0 else 0
            self.due["metrics"] = self.due["disk"] = 0
            self.store.finish(job_id, code)

    def diagnose(self):
        with self.lock:
            if self.active():
                raise ValueError("Please wait for the current operation to finish.")
            now = time.monotonic()
            if "diagnostic" not in self.futures and now >= self.diagnostic_due:
                self.futures["diagnostic"] = self.pool.submit(self.backend.diagnostics), self.epoch
                self.diagnostic_due = now + 30
            elif "diagnostic" not in self.futures:
                raise ValueError("Please wait a few seconds before checking again.")


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    def __init__(self, address, center, config, handler=None):
        self.center, self.config = center, config
        self.slots = threading.BoundedSemaphore(16)
        self.auth_lock = threading.Lock()
        self.login_failures = []
        super().__init__(address, handler or Handler)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        super().process_request(request, client_address)

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()


class Handler(BaseHTTPRequestHandler):
    server_version = "Pwnbox"
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def log_message(self, *_):
        pass  # Do not write tokens, passwords, cookies or repeated polls to journal.

    def reply(self, code, data, content_type="application/json; charset=utf-8", cookie=None):
        payload = data if isinstance(data, bytes) else json.dumps(data, allow_nan=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
        if cookie:
            self.send_header("Set-Cookie", cookie)
        self.end_headers()
        self.wfile.write(payload)

    def token(self):
        try:
            jar = cookies.SimpleCookie(self.headers.get("Cookie", ""))
            return jar["pwnbox_session"].value if "pwnbox_session" in jar else ""
        except cookies.CookieError:
            return ""

    def authenticated(self):
        return self.server.center.store.session(self.token())

    def allowed_host(self):
        return self.headers.get("Host", "").lower() == urlsplit(self.server.config["public_url"]).netloc.lower()

    def do_GET(self):
        if not self.allowed_host():
            return self.reply(403, {"error": "Invalid host."})
        path = urlsplit(self.path).path
        files = {"/": ("index.html", "text/html; charset=utf-8"),
                 "/app.js": ("app.js", "text/javascript; charset=utf-8"),
                 "/style.css": ("style.css", "text/css; charset=utf-8"),
                 "/thinkpad.svg": ("thinkpad.svg", "image/svg+xml"),
                 "/desktop.svg": ("desktop.svg", "image/svg+xml"),
                 "/icon.svg": ("icon.svg", "image/svg+xml")}
        if path in files:
            name, kind = files[path]
            return self.reply(200, (STATIC / name).read_bytes(), kind)
        session = self.authenticated()
        if not session:
            return self.reply(401, {"error": "Please sign in."})
        if path == "/api/session":
            return self.reply(200, {"csrf": session["csrf"], "demo": self.server.center.backend.demo})
        if path == "/api/snapshot":
            return self.reply(200, self.server.center.snapshot())
        return self.reply(404, {"error": "Not found."})

    def do_POST(self):
        if not self.allowed_host() or self.headers.get("Origin") != self.server.config["public_url"]:
            return self.reply(403, {"error": "Invalid request origin."})
        if self.headers.get_content_type() != "application/json" or self.headers.get("Transfer-Encoding"):
            return self.reply(415, {"error": "A valid JSON request is required."})
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if not 0 < size <= 4096:
                return self.reply(413, {"error": "The request is empty or too large."})
            data = json.loads(self.rfile.read(size))
            if not isinstance(data, dict):
                raise ValueError()
        except (ValueError, UnicodeError):
            return self.reply(400, {"error": "Invalid request data."})
        path = urlsplit(self.path).path
        secure = "; Secure" if self.server.config["public_url"].startswith("https:") else ""
        if path == "/api/login":
            password = data.get("password")
            if not isinstance(password, str) or len(password) > 256:
                return self.reply(400, {"error": "Invalid password."})
            with self.server.auth_lock:
                now = time.monotonic()
                self.server.login_failures = [x for x in self.server.login_failures if now - x < 60]
                if len(self.server.login_failures) >= 5:
                    return self.reply(429, {"error": "Please try again in one minute."})
                if not password_matches(password, self.server.config["password"]):
                    self.server.login_failures.append(now)
                    return self.reply(401, {"error": "Incorrect password."})
                token, csrf = self.server.center.store.login()
            return self.reply(200, {"csrf": csrf}, cookie=f"pwnbox_session={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age={SESSION_TTL}{secure}")
        session = self.authenticated()
        if not session or not hmac.compare_digest(self.headers.get("X-CSRF-Token", ""), session["csrf"]):
            return self.reply(403, {"error": "Invalid session or CSRF token."})
        try:
            center = self.server.center
            if path == "/api/logout":
                center.store.logout(self.token())
                return self.reply(200, {}, cookie=f"pwnbox_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0{secure}")
            if path == "/api/actions":
                action, request_id = data.get("action"), data.get("request_id")
                if not isinstance(action, str) or action not in ACTIONS or data.get("confirmed") is not True:
                    return self.reply(400, {"error": "The action is invalid or has not been confirmed."})
                if not isinstance(request_id, str) or not re.fullmatch(r"[a-zA-Z0-9-]{16,64}", request_id):
                    return self.reply(400, {"error": "Invalid request ID."})
                return self.reply(202, {"job_id": center.submit(action, request_id)})
            if path == "/api/diagnose":
                center.diagnose()
                return self.reply(202, {})
            return self.reply(404, {"error": "Not found."})
        except ValueError as exc:
            return self.reply(409, {"error": str(exc)})


class ShortcutHandler(Handler):
    """HTTP entry point: fixed HTTPS redirect only; never serve login or APIs."""
    def do_GET(self):
        self.send_response(302)
        self.send_header("Location", self.server.config["public_url"] + "/")
        self.send_header("Content-Length", "0")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()

    do_HEAD = do_GET

    def do_POST(self):
        self.send_response(405)
        self.send_header("Allow", "GET, HEAD")
        self.send_header("Content-Length", "0")
        self.end_headers()


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument("--demo", action="store_true")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--shortcut-port", type=int, help="Loopback port for an HTTP-to-HTTPS entry point")
    parser.add_argument("--config", type=Path, default=Path.home() / ".config/pwnbox/web.json")
    parser.add_argument("--state-dir", type=Path, default=Path.home() / ".local/state/pwnbox/web")
    parser.add_argument("--set-password", action="store_true")
    parser.add_argument("--public-url")
    args = parser.parse_args()
    if args.shortcut_port is not None and (not 1 <= args.shortcut_port <= 65535 or args.shortcut_port == args.port):
        parser.error("--shortcut-port must be a valid, separate port")
    if args.demo and args.shortcut_port is not None:
        parser.error("Shortcuts require a production HTTPS public_url")
    if args.set_password:
        url = (args.public_url or "").rstrip("/")
        parts = urlsplit(url)
        if parts.scheme != "https" or not parts.hostname or parts.path or parts.query or parts.fragment or parts.username:
            parser.error("--public-url must be an HTTPS origin, e.g. https://thinkpad.tailxxxx.ts.net")
        password = getpass.getpass("Control Center password (at least 12 characters): ")
        if len(password) < 12 or len(password) > 256 or password != getpass.getpass("Confirm password: "):
            parser.error("Passwords must match and contain 12–256 characters.")
        args.config.parent.mkdir(parents=True, exist_ok=True)
        record = {"public_url": url, "password": password_record(password)}
        tmp = args.config.with_suffix(".tmp")
        tmp.write_text(json.dumps(record))
        os.chmod(tmp, 0o600)
        tmp.replace(args.config)
        print("Password hash saved. Restart pwnbox-web to revoke existing sessions.")
        # Password reset revokes all existing sessions.
        if (args.state_dir / "web.sqlite3").exists():
            with sqlite3.connect(args.state_dir / "web.sqlite3") as db:
                db.execute("DELETE FROM sessions")
        return
    if args.demo:
        config = {"public_url": f"http://127.0.0.1:{args.port}", "password": password_record("pwnbox-demo")}
        if args.state_dir == parser.get_default("state_dir"):
            args.state_dir = ROOT / ".local/web-demo"
    else:
        config = json.loads(args.config.read_text())
        if not config["public_url"].startswith("https://"):
            parser.error("Production requires an HTTPS public_url behind Tailscale Serve.")
    center = ControlCenter(args.state_dir, Backend(args.demo))
    server = Server(("127.0.0.1", args.port), center, config)
    shortcut = None
    if args.shortcut_port is not None:
        shortcut = Server(("127.0.0.1", args.shortcut_port), center, config, ShortcutHandler)
        threading.Thread(target=shortcut.serve_forever, daemon=True).start()
    print(f"Pwnbox listening on 127.0.0.1:{args.port}" + (" — DEMO, password: pwnbox-demo" if args.demo else ""), flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        center.stop.set()
        if shortcut:
            shortcut.shutdown()
            shortcut.server_close()
        server.server_close()
        center.pool.shutdown(wait=False, cancel_futures=True)


if __name__ == "__main__":
    main()
