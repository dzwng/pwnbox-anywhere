#!/usr/bin/env bash
# Does not change disks, GRUB, BootOrder or NIC settings.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 2; }
user=${SUDO_USER:-}
boot_id=0000
public_key_file=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) user=${2:?Missing user}; shift 2;;
        --windows-boot-id) boot_id=${2:?Missing boot ID}; shift 2;;
        --automation-public-key) public_key_file=${2:?Missing public key file}; shift 2;;
        *) echo "Unknown option: $1" >&2; exit 2;;
    esac
done
[[ $user =~ ^[a-z_][a-z0-9_-]*[$]?$ && $user != root ]] || { echo 'Specify a non-root Kali user.' >&2; exit 2; }
id "$user" >/dev/null
[[ $boot_id =~ ^[[:xdigit:]]{4}$ ]] || exit 2
[[ -n $public_key_file && -r $public_key_file ]] || { echo 'Supply --automation-public-key path/to/key.pub.' >&2; exit 2; }
key=$(cat -- "$public_key_file")
[[ $key =~ ^ssh-ed25519[[:space:]][A-Za-z0-9+/=]+([[:space:]].*)?$ && $key != *$'\n'* && $key != *$'\r'* ]] || { echo 'Expected one ed25519 public key.' >&2; exit 2; }
ssh-keygen -lf "$public_key_file" >/dev/null || { echo 'Public key is invalid.' >&2; exit 2; }
source /etc/os-release
[[ $ID == kali && -d /sys/firmware/efi/efivars ]] || { echo 'Requires Kali booted in UEFI mode.' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
home_dir=$(getent passwd "$user" | cut -d: -f6)
keys="$home_dir/.ssh/authorized_keys"
key_blob=$(printf '%s\n' "$key" | awk '{print $2}')
restricted="restrict,command=\"/usr/local/libexec/pwnbox-kali-control\" $key"
if [[ -f $keys ]] && grep -Fq -- "$key_blob" "$keys"; then
    grep -Fxq -- "$restricted" "$keys" || { echo 'Key already exists with other options; review authorized_keys.' >&2; exit 2; }
fi
apt-get update
apt-get install -y openssh-server efibootmgr sudo ethtool
efibootmgr | grep -qi "^Boot${boot_id}[* ]" || { echo 'Configured Windows boot entry does not exist.' >&2; exit 2; }
install -d -m 0755 /etc/pwnbox /usr/local/libexec
install -m 0755 -o root -g root "$root/setup/pwnbox-kali-control" /usr/local/libexec/pwnbox-kali-control
printf '%s\n' "$boot_id" > /etc/pwnbox/windows-boot-id
chown root:root /etc/pwnbox/windows-boot-id
chmod 0644 /etc/pwnbox/windows-boot-id
tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT
printf '%s ALL=(root) NOPASSWD: /usr/local/libexec/pwnbox-kali-control windows, /usr/local/libexec/pwnbox-kali-control off\n' "$user" > "$tmp"
visudo -cf "$tmp"
install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/pwnbox-kali-control
visudo -c
install -d -m 0700 -o "$user" -g "$(id -gn "$user")" "$home_dir/.ssh"
touch "$keys"
grep -Fxq -- "$restricted" "$keys" || printf '%s\n' "$restricted" >> "$keys"
chown "$user:$(id -gn "$user")" "$keys"
chmod 0600 "$keys"
systemctl enable --now ssh
echo 'Control endpoint installed. Interactive Mac keys stay separate.'
echo 'Verify eth0 WoL persistence and host fingerprint in docs/dualboot.md and docs/ssh.md.'
