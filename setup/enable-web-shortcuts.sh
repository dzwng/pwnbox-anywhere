#!/usr/bin/env bash
# Add tailnet-only HTTP entry points. Login/control remain on existing HTTPS.
set -Eeuo pipefail
[[ $EUID != 0 && $# == 0 ]] || { echo 'Run as the controller user, without arguments.' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$root" "$HOME/.config/pwnbox/web.json" <<'PY'
import json, subprocess, sys, time, urllib.error, urllib.request
sys.path.insert(0, sys.argv[1] + '/web')
from shortcuts import plan
with open(sys.argv[2], encoding='utf-8') as config:
    url = json.load(config)['public_url']
def status(command):
    return json.loads(subprocess.check_output(['tailscale', *command, '--json'], timeout=10))
try:
    proposal = plan(status(['status']), status(['serve', 'status']), url)
except ValueError as error:
    raise SystemExit(str(error))
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect)
for attempt in range(5):
    try:
        opener.open('http://127.0.0.1:8788/', timeout=2)
    except urllib.error.HTTPError as response:
        if response.code == 302 and response.headers.get('Location') == url + '/':
            break
    except OSError:
        pass
    time.sleep(1)
else:
    raise SystemExit('Shortcut listener not ready; update the dashboard first. Serve was not changed.')
if not proposal['already']:
    # TCP forwarding preserves IP/short-name requests, bypassing Serve's HTTP Host routing.
    subprocess.run(['sudo', 'tailscale', 'serve', '--bg', '--tcp=80', 'tcp://127.0.0.1:8788'], check=True)
confirmed = plan(status(['status']), status(['serve', 'status']), url)
if not confirmed['already']:
    raise SystemExit('HTTP shortcut route was not installed; review tailscale serve status.')
print('Short addresses (Tailscale connected; redirect to HTTPS):')
for address in confirmed['urls']:
    print('  ' + address)
print('Login remains at ' + url)
PY
