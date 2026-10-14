"""Read Linux counters; no privileged commands, agents, or GPU workloads."""
import json
from pathlib import Path
import shutil
import time
import sys


class LinuxMetrics:
    def __init__(self, proc="/proc", sys="/sys", disk="/"):
        self.proc, self.sys, self.disk = Path(proc), Path(sys), disk
        self.previous = None
        self.slow = {}
        self.next_disk = self.next_health = 0

    @staticmethod
    def number(path):
        try:
            return float(Path(path).read_text().strip())
        except (OSError, ValueError):
            return None

    def sample(self, health=True, disk=True):
        now = time.monotonic()
        data = {"sampled_at": time.time(), "cpu_percent": None,
                "ram_used": None, "ram_total": None, "uptime": None}
        try:
            values = [int(x) for x in (self.proc / "stat").read_text().splitlines()[0].split()[1:9]]
            total, idle = sum(values), values[3] + values[4]
            if self.previous:
                delta = total - self.previous[0]
                if delta > 0:
                    data["cpu_percent"] = round(max(0, min(100, 100 * (1 - (idle - self.previous[1]) / delta))), 1)
            self.previous = total, idle
            mem = dict((line.split(":")[0], int(line.split()[1]) * 1024)
                       for line in (self.proc / "meminfo").read_text().splitlines())
            data["ram_total"] = mem["MemTotal"]
            # Available includes reclaimable cache, unlike MemFree.
            data["ram_used"] = max(0, mem["MemTotal"] - mem["MemAvailable"])
            data["uptime"] = float((self.proc / "uptime").read_text().split()[0])
        except (OSError, ValueError, KeyError, IndexError):
            pass
        if disk and now >= self.next_disk:
            try:
                usage = shutil.disk_usage(self.disk)
                self.slow.update(disk_used=usage.total - usage.free, disk_total=usage.total,
                                 disk_mount=self.disk, disk_sampled_at=time.time())
            except OSError:
                self.slow.update(disk_used=None, disk_total=None)
            self.next_disk = now + 60
        if health and now >= self.next_health:
            self.slow.update(temperature=None, battery_percent=None, battery_health=None, battery_status=None,
                             ac_online=None, charge_start_threshold=None, charge_stop_threshold=None)
            online = []
            for supply in self.sys.glob("class/power_supply/*"):
                try:
                    if (supply / "type").read_text().strip() in ("Mains", "USB", "USB_C", "USB_PD"):
                        value = self.number(supply / "online")
                        if value in (0, 1):
                            online.append(bool(value))
                except OSError:
                    pass
            if online:
                self.slow["ac_online"] = any(online)
            for hw in self.sys.glob("class/hwmon/hwmon*"):
                try:
                    if (hw / "name").read_text().strip() in ("coretemp", "k10temp"):
                        temperatures = [self.number(p) for p in hw.glob("temp*_input")]
                        valid = [x / 1000 for x in temperatures if x is not None]
                        if valid:
                            self.slow["temperature"] = max(valid)
                except OSError:
                    pass
            for bat in self.sys.glob("class/power_supply/BAT*"):
                self.slow["battery_percent"] = self.number(bat / "capacity")
                self.slow["charge_start_threshold"] = self.number(bat / "charge_control_start_threshold")
                self.slow["charge_stop_threshold"] = self.number(bat / "charge_control_end_threshold")
                try:
                    self.slow["battery_status"] = (bat / "status").read_text().strip()
                except OSError:
                    pass
                for kind in ("energy", "charge"):
                    full, design = self.number(bat / (kind + "_full")), self.number(bat / (kind + "_full_design"))
                    if full is not None and design:
                        self.slow["battery_health"] = round(100 * full / design, 1)
                        break
                break
            self.next_health = now + 15
        data.update(self.slow)
        return data

    def gpu(self):
        candidates = []
        for dev in self.sys.glob("class/drm/card[0-9]*/device"):
            try:
                if (dev / "vendor").read_text().strip() != "0x1002":
                    continue
                total = self.number(dev / "mem_info_vram_total")
                if total and total > 1024 ** 3:
                    candidates.append((dev, total))
            except OSError:
                pass
        if len(candidates) != 1:
            return {"gpu_percent": None, "vram_used": None, "vram_total": None,
                    "gpu_note": "Cannot identify a single discrete AMD GPU."}
        dev, total = candidates[0]
        return {"gpu_percent": self.number(dev / "gpu_busy_percent"),
                "vram_used": self.number(dev / "mem_info_vram_used"), "vram_total": total}


if __name__ == "__main__":
    # Endpoint verifies its own OS. The controller never trusts an unmarked payload.
    release = Path("/etc/os-release").read_text()
    if not any(line in ('ID=kali', 'ID="kali"') for line in release.splitlines()):
        raise SystemExit("Requires Kali")
    collector = LinuxMetrics()
    # First CPU measurement needs two observations, not lifetime average.
    collector.sample(health=False, disk=False)
    time.sleep(0.15)
    data = collector.sample(health=False, disk='--fast' not in sys.argv)
    data.update(collector.gpu(), os="KALI")
    print(json.dumps(data, allow_nan=False))
