"""Stateful SSH/WoL/liveness fixtures. Never connect to a real host."""
import base64
import os
from pathlib import Path
import sys
import time

root = Path(os.environ['MOCK_DIR'])
tool, *args = sys.argv[1:]
state_file = root / 'desktop'
state = state_file.read_text().strip()
log = root / 'actions'

def record(action):
    with log.open('a', newline='\n') as stream:
        stream.write(action + '\n')

def transition(target):
    state_file.write_text('TRANSITION:' + target)

if tool == 'python3' and args and args[0] == '-c':
    # Execute only the local UTF-16LE encoding utility, never remote instructions.
    print(base64.b64encode(sys.stdin.read().encode('utf-16le')).decode())
    sys.exit(0)

if tool == 'python3':
    if ':' in args[1]:
        record('wake')
        if state == 'OFF' and not os.environ.get('MOCK_WOL_FAIL'):
            transition('WINDOWS')
        sys.exit(0)
    sys.exit(0 if state in ('WINDOWS', 'KALI', 'ALIVE') else 1)

if tool == 'ping':
    host = args[-1]
    if host == '192.0.2.1':
        sys.exit(1 if os.environ.get('MOCK_LAN_DOWN') else 0)
    sys.exit(0 if state in ('WINDOWS', 'KALI', 'ALIVE') else 1)

assert tool == 'ssh'
command = args[-1]
os_name = 'WINDOWS' if 'HostKeyAlias=pwnbox-control-windows' in args else 'KALI'
if state.startswith('TRANSITION:'):
    state_file.write_text(state.split(':', 1)[1])
    sys.exit(255)  # At least one unreachable observation during a reboot.
if os.environ.get('MOCK_HUNG'):
    time.sleep(10)
if state != os_name and state != 'BOTH':
    sys.exit(255)
if os_name == 'WINDOWS':
    command = base64.b64decode(command.split()[-1]).decode('utf-16le')
    if 'PWNBOX_WINDOWS' in command:
        print('PWNBOX_WINDOWS')
        sys.exit(0)
    # Check safety properties of the generated command, not only its outcome.
    assert '/f' not in command and '/t 0' in command
    if 'bcdedit' in command:
        assert "'{fwbootmgr}' bootsequence '{00000000-0000-0000-0000-000000000000}'" in command
        assert command.index('if ($LASTEXITCODE -ne 0)') < command.index('shutdown.exe')
        record('windows->kali')
        if os.environ.get('MOCK_ACTION_FAIL'):
            print('bcdedit failed', file=sys.stderr)
            sys.exit(5)
        transition('KALI')
    else:
        record('windows->off')
        state_file.write_text('OFF')
else:
    if command == 'status':
        print('PWNBOX_KALI')
        sys.exit(0)
    assert command in ('windows', 'off')
    record('kali->' + command)
    if os.environ.get('MOCK_ACTION_FAIL'):
        sys.exit(5)
    if command == 'windows':
        transition('WINDOWS')
    else:
        state_file.write_text('OFF')
if os.environ.get('MOCK_DISCONNECT'):
    sys.exit(255)
print('PWNBOX_ACCEPTED')
