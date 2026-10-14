#!/usr/bin/env bash
# Install on the already configured Debian controller. No power actions.
set -Eeuo pipefail
[[ $EUID == 0 && -n ${SUDO_USER:-} && $SUDO_USER != root ]] || { echo 'Run with sudo from the controller user.' >&2; exit 2; }
[[ $# == 2 && $1 == --public-url ]] || { echo 'Usage: sudo bash setup/setup-web.sh --public-url https://thinkpad.tailxxxx.ts.net'; exit 2; }
user=$SUDO_USER
[[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || exit 2
home_dir=$(getent passwd "$user" | cut -d: -f6)
[[ $home_dir =~ ^/[a-zA-Z0-9_./-]+$ && -f $home_dir/.config/pwnbox/pwnbox.conf ]] || { echo 'Configure the existing controller first.' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
for tool in python3 ssh flock timeout; do command -v "$tool" >/dev/null || { echo "Missing $tool" >&2; exit 2; }; done
python3 - "$2" <<'PY'
import sys
from urllib.parse import urlsplit
p = urlsplit(sys.argv[1])
if p.scheme != 'https' or not p.hostname or p.path not in ('', '/') or p.query or p.fragment or p.username:
    raise SystemExit('Use the HTTPS origin shown by Tailscale Serve.')
PY
install -d -m 0755 /usr/local/lib/pwnbox/{bin,lib,web/static}
for file in pwnbox pwnbox-metrics pwnbox-diagnostics; do install -m 0755 "$root/bin/$file" "/usr/local/lib/pwnbox/bin/$file"; done
install -m 0644 "$root"/lib/*.sh /usr/local/lib/pwnbox/lib/
install -m 0644 "$root"/web/*.py "$root"/web/*.ps1 /usr/local/lib/pwnbox/web/
install -m 0644 "$root"/web/static/* /usr/local/lib/pwnbox/web/static/
install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$home_dir/.local/state/pwnbox/web"
if [[ ! -f $home_dir/.config/pwnbox/web.json ]]; then
    sudo -u "$user" env HOME="$home_dir" python3 /usr/local/lib/pwnbox/web/app.py --set-password --public-url "${2%/}"
else
    sudo -u "$user" python3 - "$home_dir/.config/pwnbox/web.json" "${2%/}" <<'PY'
import json, sys
if json.load(open(sys.argv[1]))['public_url'] != sys.argv[2]:
    raise SystemExit('Existing public_url differs. Update it with --set-password before installing.')
PY
fi
cat > /etc/systemd/system/pwnbox-web.service <<EOF
[Unit]
Description=Pwnbox Control Center
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$user
Environment=HOME=$home_dir
Environment=PYTHONDONTWRITEBYTECODE=1
WorkingDirectory=/usr/local/lib/pwnbox
ExecStart=/usr/bin/python3 /usr/local/lib/pwnbox/web/app.py --shortcut-port 8788
Restart=on-failure
RestartSec=5
UMask=0077
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=$home_dir/.local/state/pwnbox
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
TasksMax=64
MemoryMax=256M
TimeoutStopSec=10
KillMode=control-group

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable pwnbox-web.service
systemctl restart pwnbox-web.service
echo 'Control Center installed; backend listens only on 127.0.0.1:8787.'
echo 'Next: sudo tailscale serve --bg http://127.0.0.1:8787'
echo 'Review tailnet access rules so only your account/devices can reach it.'
