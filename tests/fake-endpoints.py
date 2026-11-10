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
order_file = root / 'boot-order'
order = order_file.read_text().strip().split(',')
linux = os.environ.get('MOCK_LINUX_OS', 'KALI')

def firmware(os_name):
    if os.environ.get('MOCK_FIRMWARE_UNAVAILABLE'):
        sys.exit(5)
    ids = {'WINDOWS': '{bootmgr}', linux: '{00000000-0000-0000-0000-000000000000}'} if os_name == 'WINDOWS' else {'WINDOWS': '0000', linux: '0002'}
    print('PWNBOX_BOOT_ORDER=' + ','.join(ids[name] for name in order))
    print('PWNBOX_WINDOWS_FIRST=' + str(order[0] == 'WINDOWS').lower())

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
    sys.exit(0 if state in ('WINDOWS', linux, 'ALIVE') else 1)

if tool == 'ping':
    host = args[-1]
    if host == '192.0.2.1':
        sys.exit(1 if os.environ.get('MOCK_LAN_DOWN') else 0)
    sys.exit(0 if state in ('WINDOWS', linux, 'ALIVE') else 1)

assert tool == 'ssh'
command = args[-1]
vm_file = root / 'vm'
if 'HostKeyAlias=pwnbox-control-kali-vm' in args:
    if state != 'WINDOWS' or not vm_file.exists() or vm_file.read_text() != 'RUNNING' or os.environ.get('MOCK_VM_SSH_FAIL'):
        sys.exit(255)
    if command == 'status':
        print('PWNBOX_KALI' if os.environ.get('MOCK_VM_WRONG_MARKER') else 'PWNBOX_KALI_VM')
    elif command == 'off':
        record('vm->off')
        if not os.environ.get('MOCK_VM_STAYS_ON'):
            vm_file.write_text('STOPPED')
        print('PWNBOX_ACCEPTED')
    else:
        raise AssertionError('Unexpected VM guest command')
    sys.exit(0)
os_name = next(name for name in ('WINDOWS', linux) if f'HostKeyAlias=pwnbox-control-{name.lower()}' in args)
if os.environ.get('MOCK_TRACE'):
    with (root / 'trace').open('a') as stream:
        stream.write(f'{os_name} state={state} bytes={len(command)}\n')
if state.startswith('TRANSITION:'):
    state_file.write_text(state.split(':', 1)[1])
    if os.environ.get('MOCK_ORDER_CHANGE_ON_BOOT'):
        order_file.write_text(f'{linux},WINDOWS')
    sys.exit(255)  # At least one unreachable observation during a reboot.
if os.environ.get('MOCK_HUNG'):
    time.sleep(10)
if state != os_name and state != 'BOTH':
    sys.exit(255)
if os_name == 'WINDOWS':
    command = base64.b64decode(command.split()[-1]).decode('utf-16le')
    if 'windows-vmware-control.ps1' in command:
        if os.environ.get('MOCK_VM_INVENTORY_FAIL'):
            sys.exit(5)
        if "'start'" in command:
            record('vm->start')
            if not os.environ.get('MOCK_VM_NO_START'):
                vm_file.write_text('RUNNING')
            print('PWNBOX_ACCEPTED')
        else:
            assert "'status'" in command
            print('PWNBOX_VM_RUNNING' if vm_file.read_text() == 'RUNNING' else 'PWNBOX_VM_STOPPED')
        sys.exit(0)
    if "Write-Output 'PWNBOX_WINDOWS'" in command:
        print('PWNBOX_WINDOWS')
        sys.exit(0)
    if 'Get-PwnboxBootOrder' in command and 'bootsequence ' not in command:
        assert '/set' not in command and 'shutdown.exe' not in command
        firmware('WINDOWS')
        sys.exit(0)
    # Check safety properties of the generated command, not only its outcome.
    assert '/f' not in command
    if 'bcdedit' in command:
        target = 'WINDOWS' if "bootsequence '{bootmgr}'" in command else linux
        assert "'{fwbootmgr}' bootsequence " in command
        if target == linux:
            assert "bootsequence '{00000000-0000-0000-0000-000000000000}'" in command
        reboot = 'shutdown.exe' in command
        if reboot:
            assert '/r /t 0' in command
            assert command.index('if ($LASTEXITCODE -ne 0)') < command.index('shutdown.exe')
        record('windows->' + target.lower() if reboot else 'windows->bootnext-' + target.lower())
        assert 'PWNBOX_BOOT_ORDER_BEFORE' in command and 'PWNBOX_BOOT_ORDER_AFTER_SET' in command
        if reboot:
            assert command.index('if ($before -ne $after)') < command.index('shutdown.exe')
        print('PWNBOX_BOOT_ORDER_BEFORE=' + ','.join(order))
        if os.environ.get('MOCK_ORDER_CHANGE_ON_SET'):
            order_file.write_text(f'{linux},WINDOWS')
            print(f'PWNBOX_BOOT_ORDER_AFTER_SET={linux},WINDOWS')
            sys.exit(5)
        if os.environ.get('MOCK_ACTION_FAIL'):
            print('bcdedit failed', file=sys.stderr)
            sys.exit(5)
        if reboot and not os.environ.get('MOCK_NO_REBOOT'):
            transition(target)
    else:
        assert '/s /t 0' in command
        record('windows->off')
        state_file.write_text('OFF')
else:
    if command == 'status':
        print('PWNBOX_' + os.environ.get('MOCK_LINUX_MARKER', linux))
        sys.exit(0)
    if command == 'firmware':
        firmware(linux)
        sys.exit(0)
    assert command in ('windows', 'off', 'bootnext-windows', f'bootnext-{linux.lower()}', 'reboot-windows', f'reboot-{linux.lower()}')
    record(linux.lower() + '->' + command)
    if os.environ.get('MOCK_ACTION_FAIL'):
        sys.exit(5)
    if command.startswith('bootnext-'):
        pass
    elif command.startswith('reboot-'):
        if not os.environ.get('MOCK_NO_REBOOT'):
            transition(command.split('-')[1].upper())
    elif command == 'windows':
        transition('WINDOWS')
    else:
        state_file.write_text('OFF')
if os.environ.get('MOCK_DISCONNECT'):
    sys.exit(255)
if os.environ.get('MOCK_NO_ACK'):
    sys.exit(0)
print('PWNBOX_ACCEPTED')
