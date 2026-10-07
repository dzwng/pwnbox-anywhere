"""Verify the actual packet generator against a UDP receiver on loopback only."""
from pathlib import Path
import socket
import subprocess
import sys

source = (Path(__file__).resolve().parents[1] / 'lib' / 'wol.sh').read_text()
generator = source.split("<<'PY'\n", 1)[1].split('\nPY', 1)[0]
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
    receiver.bind(('127.0.0.1', 0))
    receiver.settimeout(3)
    port = receiver.getsockname()[1]
    subprocess.run([sys.executable, '-', '02:00:00:00:00:20', '127.0.0.1', str(port)],
                   input=generator, text=True, check=True, timeout=3)
    packet, _ = receiver.recvfrom(1024)
assert len(packet) == 102
assert packet[:6] == bytes([255]) * 6
assert all(packet[6 + i * 6:12 + i * 6] == bytes([2, 0, 0, 0, 0, 32]) for i in range(16))
print('PASS: 102-byte magic packet received on loopback; no LAN broadcast.')
