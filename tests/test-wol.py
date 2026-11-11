"""Verify the actual packet generator against a UDP receiver on loopback only."""
import json
from pathlib import Path
import socket
import subprocess
import sys
from unittest.mock import patch

source = (Path(__file__).resolve().parents[1] / 'lib' / 'wol.sh').read_text()
generator = source.split("<<'PY'", 1)[1].split('\n', 1)[1].split('\nPY', 1)[0]
mac = '02:00:00:00:00:20'
expected = b'\xff' * 6 + bytes.fromhex(mac.replace(':', '')) * 16
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
    receiver.bind(('127.0.0.1', 0))
    receiver.settimeout(3)
    port = receiver.getsockname()[1]
    subprocess.run([sys.executable, '-', mac, '127.0.0.1', str(port), ''],
                   input=generator, text=True, check=True, timeout=3)
    packet, _ = receiver.recvfrom(1024)
    assert packet == expected

    route = json.dumps([{'dev': 'eth0', 'prefsrc': '127.0.0.1'}])
    addresses = json.dumps([{'addr_info': [
        {'local': '192.0.2.20', 'broadcast': '192.0.2.255'},
        {'local': '127.0.0.1', 'broadcast': '127.0.0.1'},
    ]}])
    with patch.object(sys, 'argv', ['-', mac, 'auto', str(port), '127.0.0.2']):
        with patch.object(subprocess, 'check_output', side_effect=[route, addresses]) as ip:
            exec(generator, {})
        assert ip.call_args_list[0].args[0] == ['ip', '-j', '-4', 'route', 'get', '127.0.0.2']
        assert ip.call_args_list[1].args[0] == ['ip', '-j', '-4', 'addr', 'show', 'dev', 'eth0']
        packet, peer = receiver.recvfrom(1024)
        assert packet == expected and peer[0] == '127.0.0.1'

        routed = json.dumps([{'dev': 'eth0', 'prefsrc': '127.0.0.1', 'gateway': '192.0.2.1'}])
        with patch.object(subprocess, 'check_output', return_value=routed):
            try:
                exec(generator, {})
            except SystemExit as error:
                assert 'on-link IPv4 peer' in str(error)
            else:
                raise AssertionError('Auto broadcast accepted a routed LAN health host')
print('PASS: explicit and auto destinations sent 102-byte magic packets on loopback only.')
