#!/usr/bin/env bash
# Add the Mac public key as the current Kali user's ordinary interactive SSH key.
set -Eeuo pipefail
[[ $EUID != 0 ]] || { echo 'Run as your Kali user, without sudo.' >&2; exit 2; }
source /etc/os-release
[[ $ID == kali ]] || { echo 'Run this on Kali bare-metal.' >&2; exit 2; }
[[ $# == 1 && -r $1 ]] || { echo 'Usage: setup-kali-interactive.sh /path/mac-key.pub' >&2; exit 2; }
key=$(cat -- "$1")
key=${key%$'\r'}
[[ $key =~ ^ssh-ed25519[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ && $key != *$'\n'* && $key != *$'\r'* ]] || { echo 'Expected one ed25519 public key.' >&2; exit 2; }
ssh-keygen -lf "$1"
blob=$(printf '%s\n' "$key" | awk '{print $2}')
keys=$HOME/.ssh/authorized_keys
if [[ -f $keys ]] && grep -Fq -- "$blob" "$keys"; then
    awk -v blob="$blob" '$1 == "ssh-ed25519" && $2 == blob { found = 1 } END { exit !found }' "$keys" || { echo 'Key exists with restricted options; keep automation and interactive keys separate.' >&2; exit 2; }
    echo 'Interactive key is already installed.'
    exit 0
fi
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$keys"
# Ensure a missing final newline cannot join the new key to an existing entry.
printf '\n%s\n' "$key" >> "$keys"
chmod 600 "$keys"
echo "Mac interactive key installed for $(id -un). Existing keys preserved."
