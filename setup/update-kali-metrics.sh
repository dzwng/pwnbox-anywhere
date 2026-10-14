#!/usr/bin/env bash
# Update existing restricted endpoint without changing keys, EFI or sudoers.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 2; }
source /etc/os-release
[[ $ID == kali && -f /usr/local/libexec/pwnbox-kali-control ]] || { echo 'Existing Kali controller required.' >&2; exit 2; }
command -v python3 >/dev/null
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
install -m 0644 -o root -g root "$root/web/metrics.py" /usr/local/libexec/pwnbox-linux-metrics.py
install -m 0755 -o root -g root "$root/setup/pwnbox-kali-control" /usr/local/libexec/pwnbox-kali-control
echo 'Read-only metrics enabled. Keys, sudoers and boot settings preserved.'
