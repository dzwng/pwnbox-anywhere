"""Exercise updater parameter binding and transport arguments without SSH/SCP."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == "nt", "Windows PowerShell test")
class WindowsDeployTests(unittest.TestCase):
    def setUp(self):
        parent = ROOT / ".local/deploy-tests"
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=parent)
        self.root = Path(self.temp.name)
        (self.root / "setup").mkdir()
        self.updater = self.root / "setup/update-thinkpad-from-windows.ps1"
        shutil.copyfile(ROOT / "setup/update-thinkpad-from-windows.ps1", self.updater)
        self.archive = self.root / ".local/releases/pwnbox-vmware.tar.gz"
        self.archive.parent.mkdir(parents=True)
        self.archive.write_bytes(b"local test payload; never uploaded")
        self.checksum = Path(str(self.archive) + ".sha256")
        self.checksum.write_text(hashlib.sha256(self.archive.read_bytes()).hexdigest()
                                 + "  pwnbox-vmware.tar.gz\n", encoding="ascii")

    def tearDown(self):
        self.temp.cleanup()

    def run_ps(self, script, *args):
        # A Python child of PowerShell 7 otherwise passes its bundled module path
        # to Windows PowerShell 5.1. Let 5.1 initialize its own standard modules.
        environment = {key: value for key, value in os.environ.items() if key.lower() != "psmodulepath"}
        return subprocess.run([shutil.which("powershell.exe"), "-NoProfile", "-NonInteractive",
            "-ExecutionPolicy", "Bypass", "-File", str(script), *map(str, args)],
            cwd=self.root, env=environment, capture_output=True, text=True, timeout=20)

    def test_file_invocation_resolves_default_archive_before_checksum_guard(self):
        # Invoke exactly as the user did. A bad digest stops before any transport.
        self.checksum.write_text("0" * 64 + "  pwnbox-vmware.tar.gz\n", encoding="ascii")
        result = self.run_ps(self.updater)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Archive checksum mismatch", result.stderr)
        self.assertNotIn("Join-Path", result.stderr)
        self.assertNotIn("empty string", result.stderr)

    def test_success_uses_default_or_explicit_archive_and_preserves_remote_script(self):
        launcher = self.root / "mock.ps1"
        launcher.write_text(r'''
param([string]$Updater, [string]$Archive)
function scp {
    Write-Output ('MOCK_SCP=' + (ConvertTo-Json -InputObject @($args) -Compress))
    $global:LASTEXITCODE = 0
}
function ssh {
    Write-Output ('MOCK_SSH=' + (ConvertTo-Json -InputObject @($args) -Compress))
    $global:LASTEXITCODE = 0
}
if ($Archive) { & $Updater -Archive $Archive } else { & $Updater }
''', encoding="utf-8-sig")
        for arguments in ((), (self.archive,)):
            with self.subTest(explicit=bool(arguments)):
                result = self.run_ps(launcher, self.updater, *arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                records = dict(line.split("=", 1) for line in result.stdout.splitlines() if line.startswith("MOCK_"))
                scp_args = json.loads(records["MOCK_SCP"])
                ssh_args = json.loads(records["MOCK_SSH"])
                self.assertEqual(Path(scp_args[2]), self.archive)
                self.assertEqual(scp_args[-1], "zwng@pwnbox-relay:./")
                self.assertEqual(ssh_args[:4], ["-t", "-o", "StrictHostKeyChecking=yes", "zwng@pwnbox-relay"])
                self.assertIn('cd "$HOME"\n', ssh_args[-1])
                self.assertIn("bash setup/update-web.sh", ssh_args[-1])
                self.assertNotIn("\r", ssh_args[-1])
