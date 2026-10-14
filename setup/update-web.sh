#!/usr/bin/env bash
# Update an installed dashboard; preserve password, data and Tailscale routes.
set -Eeuo pipefail
[[ $# == 0 || ( $# == 1 && $1 == --shortcuts ) ]] || { echo 'Usage: bash setup/update-web.sh [--shortcuts]' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
url=$(python3 - "$HOME/.config/pwnbox/web.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['public_url'])
PY
)
sudo bash "$root/setup/setup-web.sh" --public-url "$url"
systemctl is-active pwnbox-web.service
if [[ ${1:-} == --shortcuts ]]; then
    bash "$root/setup/enable-web-shortcuts.sh"
fi
echo "Updated Control Center: $url"
echo 'Password/history/Tailscale Serve preserved. Refresh the dashboard.'
