#!/usr/bin/env bash
# Upgrade an existing endpoint. Does not set BootNext or reboot the desktop.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 2; }
user=${SUDO_USER:-}
kali_boot_id=
while [[ $# -gt 0 ]]; do
    case "$1" in
        --user) user=${2:?Missing user}; shift 2;;
        --kali-boot-id) kali_boot_id=${2:?Missing boot ID}; shift 2;;
        *) echo "Unknown option: $1" >&2; exit 2;;
    esac
done
source /etc/os-release
[[ $ID == kali && -d /sys/firmware/efi/efivars && -f /usr/local/libexec/pwnbox-kali-control && -f /etc/sudoers.d/pwnbox-kali-control ]] || { echo 'Existing Kali UEFI controller required.' >&2; exit 2; }
[[ $user =~ ^[a-z_][a-z0-9_-]*[$]?$ && $user != root ]] || { echo 'Specify the existing non-root controller user with --user.' >&2; exit 2; }
id "$user" >/dev/null
awk -v user="$user" '$1 == user && $2 == "ALL=(root)" { found=1 } END { exit !found }' /etc/sudoers.d/pwnbox-kali-control || { echo 'User does not match the installed controller sudoers.' >&2; exit 2; }
if [[ -z $kali_boot_id && -f /etc/pwnbox/kali-boot-id ]]; then
    read -r kali_boot_id < /etc/pwnbox/kali-boot-id
fi
[[ $kali_boot_id =~ ^[[:xdigit:]]{4}$ ]] || { echo 'Supply --kali-boot-id with the verified Kali EFI entry from efibootmgr -v.' >&2; exit 2; }
read -r windows_boot_id < /etc/pwnbox/windows-boot-id
[[ $windows_boot_id =~ ^[[:xdigit:]]{4}$ && ${windows_boot_id^^} != ${kali_boot_id^^} ]] || exit 2
for boot_id in "$windows_boot_id" "$kali_boot_id"; do
    efibootmgr | grep -i "^Boot${boot_id}[* ]" >/dev/null || { echo "Firmware entry $boot_id not found." >&2; exit 2; }
done
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp)
trap 'rm -f -- "$tmp"' EXIT
printf '%s ALL=(root) NOPASSWD: /usr/local/libexec/pwnbox-kali-control bootnext-windows, /usr/local/libexec/pwnbox-kali-control bootnext-kali, /usr/local/libexec/pwnbox-kali-control reboot-windows, /usr/local/libexec/pwnbox-kali-control reboot-kali, /usr/local/libexec/pwnbox-kali-control firmware\n' "$user" > "$tmp"
visudo -cf "$tmp"
printf '%s\n' "$kali_boot_id" > /etc/pwnbox/kali-boot-id
chown root:root /etc/pwnbox/kali-boot-id
chmod 0644 /etc/pwnbox/kali-boot-id
install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/pwnbox-kali-boot-control
visudo -c
install -m 0644 -o root -g root "$root/web/metrics.py" /usr/local/libexec/pwnbox-linux-metrics.py
install -m 0755 -o root -g root "$root/setup/pwnbox-kali-control" /usr/local/libexec/pwnbox-kali-control
echo 'BootNext/reboot controls enabled. No firmware or power action sent; SSH keys preserved.'
