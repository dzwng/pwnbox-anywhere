#!/usr/bin/env bash
# Interactive deployment from the existing controller account. No power commands.
set -Eeuo pipefail
[[ $EUID != 0 ]] || { echo 'Run as the controller user, without sudo.' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ -f $HOME/.config/pwnbox/pwnbox.conf ]] || { echo 'Existing controller config required.' >&2; exit 2; }
for tool in python3 tailscale sudo; do command -v "$tool" >/dev/null || exit 2; done

# Prefer a free HTTPS listener; never replace an existing Serve route.
public_url=$(python3 - <<'PY'
import json, re, subprocess
node = json.loads(subprocess.check_output(['tailscale', 'status', '--json'], timeout=10))
name = node.get('Self', {}).get('DNSName', '').rstrip('.')
if not re.fullmatch(r'[a-zA-Z0-9.-]+\.ts\.net', name):
    raise SystemExit('ThinkPad needs a Tailscale MagicDNS name before deployment.')
serve = json.loads(subprocess.check_output(['tailscale', 'serve', 'status', '--json'], timeout=10))
if not isinstance(serve, dict):
    raise SystemExit('Unrecognized Serve configuration; review it before deployment.')
port = 8443 if serve else 443
if str(port) in serve.get('TCP', {}) or any(str(k).endswith(':' + str(port)) for k in serve.get('Web', {})):
    raise SystemExit('HTTPS 8443 is already configured. Existing services preserved; select a free port manually.')
if serve.get('AllowFunnel'):
    raise SystemExit('Funnel is configured. Review Serve/Funnel routing before adding the private control service.')
print('https://' + name + (':8443' if port == 8443 else ''))
PY
)
printf 'Install URL: %s\n' "$public_url"
tailscale serve status
sudo bash "$root/setup/setup-web.sh" --public-url "$public_url"

# Verify the loopback backend has started before adding the HTTPS route.
python3 - "$public_url" <<'PY'
import sys, time, urllib.request
from urllib.parse import urlsplit
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
request = urllib.request.Request('http://127.0.0.1:8787/', headers={'Host': urlsplit(sys.argv[1]).netloc})
for attempt in range(5):
    try:
        with opener.open(request, timeout=2) as response:
            if response.status == 200 and b'Pwnbox Control Center' in response.read():
                break
    except OSError:
        pass
    time.sleep(1)
else:
    raise SystemExit('Backend did not start. Check journalctl -u pwnbox-web; Serve was not changed.')
PY
if [[ $public_url == *:8443 ]]; then
    sudo tailscale serve --bg --https=8443 http://127.0.0.1:8787
else
    sudo tailscale serve --bg --https=443 http://127.0.0.1:8787
fi
systemctl is-active pwnbox-web
tailscale serve status
printf '\nControl Center: %s\n' "$public_url"
echo 'Open this URL from a Tailscale-connected device and use the web password you just set.'
echo 'Kali metrics need setup/update-kali-metrics.sh on Kali; no desktop reboot has been sent.'
