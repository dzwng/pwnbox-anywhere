"""SSH replacement: validates fixed metrics command, never connects."""
import base64
import json
import os
import sys

args = sys.argv[1:]
target = os.environ["EXPECT_OS"]
mode = os.environ["EXPECT_MODE"]
for option in ("BatchMode=yes", "IdentitiesOnly=yes", "StrictHostKeyChecking=yes",
               "HostKeyAlias=pwnbox-control-" + target.lower(), "ControlMaster=auto", "ControlPersist=15s"):
    assert option in args, option
assert any("/metrics-" + target.lower() + "-" in x and x.endswith(".sock") for x in args)
if target == "KALI":
    assert args[-1] == ("metrics" if mode == "disk" else "metrics-fast")
else:
    assert len(args[-1]) < 8000, 'Windows cmd.exe command length limit'
    command = base64.b64decode(args[-1].split()[-1]).decode("utf-16le")
    assert command.startswith("$PwnboxReadDisk=" + ("$true" if mode == "disk" else "$false") + "; ")
    assert "ConvertTo-Json -Compress" in command
    assert "shutdown.exe" not in command and "bcdedit" not in command
print(json.dumps({"os": target, "cpu_percent": 12, "gpu_percent": 5}))
