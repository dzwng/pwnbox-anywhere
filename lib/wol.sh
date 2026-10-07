#!/usr/bin/env bash
send_wol() {
    log "Sending Wake-on-LAN to $DESKTOP_MAC via $WOL_BROADCAST:$WOL_PORT..."
    timeout --kill-after=1 5 python3 - "$DESKTOP_MAC" "$WOL_BROADCAST" "$WOL_PORT" <<'PY'
import socket, sys
packet = b'\xff' * 6 + bytes.fromhex(sys.argv[1].replace(':', '')) * 16
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.settimeout(2)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.sendto(packet, (sys.argv[2], int(sys.argv[3])))
PY
}
