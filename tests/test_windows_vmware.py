"""Run the Windows helper against a fake vmrun and mocked Scheduled Tasks only."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == "nt", "Windows PowerShell test")
class WindowsVMwareTests(unittest.TestCase):
    def execute(self, action, inventory, code=0, disabled=False):
        parent = ROOT / ".local/vmware-tests"
        parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent) as directory:
            directory = Path(directory)
            control = directory / "pwnbox"
            control.mkdir()
            vmx = directory / "Kali guest.vmx"
            vmx.touch()
            vmrun = directory / "vmrun.ps1"
            lines = [line.replace("VMX", str(vmx)) for line in inventory]
            vmrun.write_text("\n".join("Write-Output '" + line.replace("'", "''") + "'" for line in lines)
                             + f"\nexit {code}\n", encoding="utf-8-sig")
            (control / "vmware.json").write_text(json.dumps({"VmxPath": str(vmx), "VmrunPath": str(vmrun)}))
            helper = ROOT / "setup/windows-vmware-control.ps1"
            script = directory / "test.ps1"
            script.write_text("""
param([string]$DataDir, [string]$Helper, [string]$Action)
$env:ProgramData = $DataDir
function Get-ScheduledTask { [pscustomobject]@{State='STATE'} }
function Start-ScheduledTask { param($TaskName); if ($TaskName -ne 'Pwnbox Kali VMware') { throw 'Wrong task' }; Write-Output 'MOCK_START' }
function shutdown.exe { throw 'Host power action forbidden' }
function bcdedit.exe { throw 'Firmware action forbidden' }
& $Helper $Action
exit $LASTEXITCODE
""".replace("STATE", "Disabled" if disabled else "Ready"), encoding="utf-8-sig")
            return subprocess.run([shutil.which("powershell.exe"), "-NoProfile", "-NonInteractive",
                "-ExecutionPolicy", "Bypass", "-File", str(script), str(directory), str(helper), action],
                capture_output=True, text=True, timeout=20)

    def test_status_uses_exact_vmx_path(self):
        for inventory, expected in ((["Total running VMs: 0"], "STOPPED"),
                                    (["Total running VMs: 1", "VMX"], "RUNNING"),
                                    (["Total running VMs: 1", "VMX.other"], "STOPPED")):
            with self.subTest(inventory=inventory):
                result = self.execute("status", inventory)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "PWNBOX_VM_" + expected)

    def test_bad_inventory_never_becomes_stopped(self):
        for lines, code in ((["Error: unavailable"], 0), (["Total running VMs: 0"], 1),
                            (["Total running VMs: 1"], 0)):
            result = self.execute("status", lines, code)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("PWNBOX_VM_STOPPED", result.stdout)

    def test_start_is_single_task_request_and_running_vm_is_idempotent(self):
        result = self.execute("start", ["Total running VMs: 0"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("MOCK_START"), 1)
        self.assertIn("PWNBOX_ACCEPTED", result.stdout)
        result = self.execute("start", ["Total running VMs: 1", "VMX"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("MOCK_START", result.stdout)

    def test_disabled_task_refuses_start(self):
        result = self.execute("start", ["Total running VMs: 0"], disabled=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("PWNBOX_ACCEPTED", result.stdout)


if __name__ == "__main__":
    unittest.main()
