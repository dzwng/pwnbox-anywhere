#!/usr/bin/env bash
# Run as the existing controller user, without sudo. No connections or power actions.
set -Eeuo pipefail
[[ $EUID != 0 && $# == 1 && $1 =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo 'Usage: bash setup/prepare-vmware-thinkpad.sh VM_USER (not sudo)' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
umask 077
mkdir -p "$HOME/.ssh" "$HOME/.config/pwnbox"
key=$HOME/.ssh/pwnbox_control_kali_vm
if [[ -e $key || -e $key.pub ]]; then
    [[ -f $key && -f $key.pub ]] || { echo 'Incomplete existing VM key pair; inspect before proceeding.' >&2; exit 2; }
    ssh-keygen -lf "$key.pub"
else
    ssh-keygen -t ed25519 -a 100 -N '' -f "$key" -C thinkpad-control-kali-vm
fi
touch "$HOME/.ssh/pwnbox_vm_known_hosts"
chmod 600 "$key" "$HOME/.ssh/pwnbox_vm_known_hosts"
config=$HOME/.config/pwnbox/vmware.conf
if [[ ! -e $config ]]; then
    sed "s/^VM_USER=.*/VM_USER=$1/" "$root/config/vmware.conf.example" > "$config"
    chmod 600 "$config"
fi
printf 'Preserved existing config/key. Profile: %s\n' "$config"
echo 'Copy ONLY this new public key to the VM (never the private key):'
cat "$key.pub"
echo 'Keep VM_ENABLED=false until guest setup and host fingerprint verification are complete. See docs/vmware.md.'
