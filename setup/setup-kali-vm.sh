#!/usr/bin/env bash
# Run INSIDE the old VMware guest. Does not install bare-metal/EFI control.
set -Eeuo pipefail
[[ $EUID == 0 && $# == 3 ]] || { echo 'Usage: sudo bash setup/setup-kali-vm.sh USER AUTOMATION.pub MAC_INTERACTIVE.pub' >&2; exit 2; }
user=$1
[[ $user =~ ^[a-z_][a-z0-9_-]*$ && $user != root ]] || exit 2
id "$user" >/dev/null
source /etc/os-release
[[ $ID == kali && $(systemd-detect-virt --vm) == vmware ]] || { echo 'Requires a Kali VMware guest, not Kali dual boot.' >&2; exit 2; }
for file in "$2" "$3"; do
    [[ -f $file && $(wc -l < "$file") -le 1 ]] || exit 2
    key=$(cat -- "$file")
    [[ $key =~ ^ssh-ed25519[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ && $key != *$'\r'* && $key != *$'\n'* ]] || exit 2
    ssh-keygen -lf "$file" >/dev/null
done
automation=$(cat -- "$2") interactive=$(cat -- "$3")
[[ $(awk '{print $2}' <<< "$automation") != "$(awk '{print $2}' <<< "$interactive")" ]] || { echo 'Use separate automation and interactive keys.' >&2; exit 2; }
home_dir=$(getent passwd "$user" | cut -d: -f6)
keys=$home_dir/.ssh/authorized_keys
restricted="restrict,command=\"/usr/local/libexec/pwnbox-kali-vm-control\" $automation"
if [[ -f $keys ]]; then
    for entry in "$restricted" "$interactive"; do
        # Match actual public key blobs, including keys with multi-word comments.
        if [[ $entry == "$restricted" ]]; then blob=$(awk '{print $2}' <<< "$automation"); else blob=$(awk '{print $2}' <<< "$interactive"); fi
        if grep -Fq -- "$blob" "$keys"; then
            grep -Fxq -- "$entry" "$keys" || { echo 'Key exists with different options; review authorized_keys first.' >&2; exit 2; }
        fi
    done
fi
apt-get update
apt-get install -y openssh-server sudo open-vm-tools
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
install -d -m 0755 /usr/local/libexec
install -m 0755 -o root -g root "$root/setup/pwnbox-kali-vm-control" /usr/local/libexec/pwnbox-kali-vm-control
tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT
printf '%s ALL=(root) NOPASSWD: /usr/local/libexec/pwnbox-kali-vm-control off\n' "$user" > "$tmp"
visudo -cf "$tmp"
install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/pwnbox-kali-vm-control
install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$home_dir/.ssh"
[[ ! -f $keys ]] || cp -p -- "$keys" "$keys.before-vm-$(date +%s)"
touch "$keys"
for entry in "$restricted" "$interactive"; do
    grep -Fxq -- "$entry" "$keys" || printf '\n%s\n' "$entry" >> "$keys"
done
chown "$user:$(id -gn "$user")" "$keys"
chmod 0600 "$keys"
systemctl enable --now ssh
echo 'VM endpoint installed. Existing keys/VNC/Tailscale preserved. No boot or power action sent.'
