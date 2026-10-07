#!/usr/bin/env bash
# Install code without changing power settings, firewall, keys or Tailscale.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo from the controller user.' >&2; exit 2; }
user=${SUDO_USER:-}
[[ -n $user && $user != root ]] || { echo 'Run with sudo from a non-root account.' >&2; exit 2; }
home_dir=$(getent passwd "$user" | cut -d: -f6)
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
apt-get update
apt-get install -y openssh-client openssh-server python3 coreutils util-linux iputils-ping
systemctl enable --now ssh
install -d -m 0755 /usr/local/lib/pwnbox/bin /usr/local/lib/pwnbox/lib
install -m 0755 "$root/bin/pwnbox" /usr/local/lib/pwnbox/bin/pwnbox
install -m 0644 "$root"/lib/*.sh /usr/local/lib/pwnbox/lib/
printf '#!/bin/sh\nexec /usr/local/lib/pwnbox/bin/pwnbox "$@"\n' > /usr/local/bin/pwnbox
chmod 0755 /usr/local/bin/pwnbox
install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$home_dir/.config/pwnbox" "$home_dir/.ssh"
if [[ ! -e $home_dir/.config/pwnbox/pwnbox.conf ]]; then
    install -m 0600 -o "$user" -g "$(id -gn "$user")" "$root/config/pwnbox.conf.example" "$home_dir/.config/pwnbox/pwnbox.conf"
fi
printf 'Installed for %s. Existing config preserved.\n' "$user"
printf 'Next: configure LAN values, install automation keys, verify host keys; see docs/ssh.md.\n'
