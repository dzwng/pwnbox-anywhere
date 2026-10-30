#!/usr/bin/env bash
# Verify host/port/socket separation without SSH, SCP or VNC connections.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
source "$root/macos-pwnbox.zsh.example"
PWNBOX_KALI_HOST=kali PWNBOX_VM_HOST=kali-vm
PWNBOX_VNC_SOCKET=$work/dual-vnc PWNBOX_SOCKS_SOCKET=$work/dual-socks
PWNBOX_VM_VNC_SOCKET=$work/vm-vnc PWNBOX_VM_SOCKS_SOCKET=$work/vm-socks
ssh() {
    printf '%s\n' "$*" >> "$work/ssh"
    [[ " $* " != *' -O check '* ]]
}
scp() { printf '%s\n' "$*" >> "$work/scp"; }
pwnbox_vnc > /dev/null
pwnbox_vm_vnc > /dev/null
proxy_up
proxy_vm_up
pwnbox_vm_down
kali_vm_pull '~/loot' .
kali_vm_push ./example '~/htb'
grep -q -- "-S $work/dual-vnc .*127.0.0.1:5901:127.0.0.1:5901 kali$" "$work/ssh"
grep -q -- "-S $work/vm-vnc .*127.0.0.1:5902:127.0.0.1:5901 kali-vm$" "$work/ssh"
grep -q -- "-S $work/dual-socks .*127.0.0.1:1080 kali$" "$work/ssh"
grep -q -- "-S $work/vm-socks .*127.0.0.1:1081 kali-vm$" "$work/ssh"
grep -q -- '/usr/local/bin/pwnbox vm-stop$' "$work/ssh"
! grep -q -- '/usr/local/bin/pwnbox off$' "$work/ssh"
grep -q -- 'kali-vm:~/loot' "$work/scp"
grep -q -- 'kali-vm:~/htb' "$work/scp"
[[ $PWNBOX_KALI_HOST == kali && $PWNBOX_VNC_SOCKET == "$work/dual-vnc" ]]
echo 'PASS: dual-boot/VM SSH targets, VNC/SOCKS ports, sockets and guest-only down command.'
