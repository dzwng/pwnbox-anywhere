#!/usr/bin/env bash
send_wol() {
    timeout --kill-after=1 5 python3 - "$DESKTOP_MAC" "$WOL_BROADCAST" "$WOL_PORT" "$LAN_HEALTH_HOST" <<'PY' || fail 5 'Wake-on-LAN send failed. Check the ThinkPad LAN route and WOL_BROADCAST.'
import json
import socket
import subprocess
import sys


def lan_broadcast(host):
    if not host:
        raise ValueError("LAN_HEALTH_HOST is empty")
    peer = socket.gethostbyname(host)
    route, = json.loads(subprocess.check_output(["ip", "-j", "-4", "route", "get", peer]))
    if route.get("gateway") or route.get("type", "unicast") != "unicast":
        raise ValueError("LAN_HEALTH_HOST must be an on-link IPv4 peer")
    source = route["prefsrc"]
    link, = json.loads(subprocess.check_output(["ip", "-j", "-4", "addr", "show", "dev", route["dev"]]))
    for address in link["addr_info"]:
        if address.get("local") == source and address.get("broadcast"):
            return address["broadcast"], source
    raise ValueError(f"No IPv4 broadcast for {source} on {route['dev']}")


mac, destination, port, lan_host = sys.argv[1:]
source = ""
if destination == "auto":
    try:
        destination, source = lan_broadcast(lan_host)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        sys.exit(f"Cannot derive Wake-on-LAN broadcast from LAN_HEALTH_HOST: {error}")
packet = b'\xff' * 6 + bytes.fromhex(mac.replace(':', '')) * 16
try:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(2)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        if source:
            sock.bind((source, 0))
        sock.sendto(packet, (destination, int(port)))
except OSError as error:
    sys.exit(f"Cannot send Wake-on-LAN to {destination}:{port}: {error}")
via = f" from {source}" if source else ""
print(f"[pwnbox] Wake-on-LAN sent to {mac} via {destination}:{port}{via}.", file=sys.stderr)
PY
}
