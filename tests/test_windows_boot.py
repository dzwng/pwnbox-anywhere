"""Execute generated Windows boot controls against PowerShell command mocks only."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TEST_DIR = ROOT / ".local" / "boot-tests"
BCD_ORDER = """Firmware Boot Manager
---------------------
identifier              {fwbootmgr}
displayorder            {bootmgr}
                        {00000000-0000-0000-0000-000000000000}
timeout                 1
"""
BCD_REVERSED = BCD_ORDER.replace(
    "displayorder            {bootmgr}\n                        {00000000-0000-0000-0000-000000000000}",
    "displayorder            {00000000-0000-0000-0000-000000000000}\n                        {bootmgr}")


@unittest.skipUnless(os.name == "nt", "Windows PowerShell execution test")
class WindowsBootTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bash = os.environ.get("PWNBOX_TEST_BASH", "C:/Program Files/Git/bin/bash.exe")
        cls.powershell = shutil.which("powershell.exe")
        if not Path(cls.bash).is_file() or not cls.powershell:
            raise unittest.SkipTest("Git Bash and Windows PowerShell required")
        TEST_DIR.mkdir(parents=True, exist_ok=True)

    def execute(self, operation, before=BCD_ORDER, after=BCD_ORDER, set_code=0, enum_code=0):
        # Override transport and evaluate only the generated PowerShell command.
        generated = subprocess.run([self.bash, "-c", """
source lib/windows.sh
KALI_WINDOWS_BCD_GUID='{00000000-0000-0000-0000-000000000000}'
remote_action() { printf '%s' "$2"; }
windows_ps() { printf '%s' "$1"; }
case "$1" in
    reboot) windows_reboot KALI;;
    bootnext) windows_bootnext KALI;;
    firmware) windows_firmware;;
esac
""", "test", operation], cwd=ROOT, capture_output=True, text=True, timeout=15, check=True).stdout
        with tempfile.TemporaryDirectory(dir=TEST_DIR) as directory:
            directory = Path(directory)
            config = directory / "fixtures.json"
            config.write_text(json.dumps(dict(before=before, after=after, set_code=set_code,
                                               enum_code=enum_code)), encoding="utf-8")
            mock = r"""
param([string]$FixtureFile)
$script:fixture = Get-Content -LiteralPath $FixtureFile -Raw | ConvertFrom-Json
$script:reads = 0
function bcdedit.exe {
    if ($args[0] -eq '/enum') {
        $script:reads++
        $global:LASTEXITCODE = [int]$script:fixture.enum_code
        if ($script:reads -eq 1) { $script:fixture.before -split "`n" }
        else { $script:fixture.after -split "`n" }
    } elseif ($args[0] -eq '/set' -and $args[1] -eq '{fwbootmgr}' -and $args[2] -eq 'bootsequence') {
        Write-Output 'MOCK_SET_BOOTNEXT'
        $global:LASTEXITCODE = [int]$script:fixture.set_code
    } else { throw 'Unexpected firmware mutation' }
}
function shutdown.exe {
    if (($args -join ' ') -ne '/r /t 0') { throw 'Unexpected power command' }
    Write-Output 'MOCK_REBOOT'
    $global:LASTEXITCODE = 0
}
"""
            script = directory / "test.ps1"
            script.write_text(mock + "\n" + generated, encoding="utf-8-sig")
            return subprocess.run([self.powershell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy",
                                   "Bypass", "-File", str(script), str(config)],
                                  capture_output=True, text=True, timeout=15)

    def test_reboot_preserves_order_and_reports_both_snapshots(self):
        result = self.execute("reboot")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PWNBOX_BOOT_ORDER_BEFORE={bootmgr},", result.stdout)
        self.assertIn("PWNBOX_BOOT_ORDER_AFTER_SET={bootmgr},", result.stdout)
        self.assertIn("MOCK_REBOOT", result.stdout)
        self.assertIn("PWNBOX_ACCEPTED", result.stdout)

    def test_order_change_cancels_reboot_and_retains_evidence(self):
        result = self.execute("reboot", after=BCD_REVERSED)
        self.assertEqual(result.returncode, 5)
        self.assertIn("PWNBOX_BOOT_ORDER_AFTER_SET={00000000", result.stdout)
        self.assertNotIn("MOCK_REBOOT", result.stdout)
        self.assertNotIn("PWNBOX_ACCEPTED", result.stdout)

    def test_failed_bcdedit_does_not_reboot(self):
        result = self.execute("reboot", set_code=5)
        self.assertEqual(result.returncode, 5)
        self.assertNotIn("MOCK_REBOOT", result.stdout)

    def test_unreadable_or_unparseable_order_does_not_set_bootnext(self):
        for fixtures in (dict(enum_code=5), dict(before="No firmware manager")):
            with self.subTest(fixtures=fixtures):
                result = self.execute("reboot", **fixtures)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("MOCK_SET_BOOTNEXT", result.stdout)
                self.assertNotIn("MOCK_REBOOT", result.stdout)

    def test_bootnext_without_reboot(self):
        result = self.execute("bootnext")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PWNBOX_ACCEPTED", result.stdout)
        self.assertNotIn("MOCK_REBOOT", result.stdout)

    def test_read_only_snapshot_excludes_pending_bootsequence(self):
        result = self.execute("firmware", before=BCD_ORDER +
                              "bootsequence            {00000000-0000-0000-0000-000000000000}\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        order = next(line for line in result.stdout.splitlines() if line.startswith("PWNBOX_BOOT_ORDER="))
        self.assertEqual(order.count("{00000000"), 1)
        self.assertIn("PWNBOX_WINDOWS_FIRST=true", result.stdout)
        self.assertNotIn("MOCK_SET_BOOTNEXT", result.stdout)
        self.assertNotIn("MOCK_REBOOT", result.stdout)
        result = self.execute("firmware", before=BCD_REVERSED)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PWNBOX_WINDOWS_FIRST=false", result.stdout)


if __name__ == "__main__":
    unittest.main()
