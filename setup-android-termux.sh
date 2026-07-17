#!/data/data/com.termux/files/usr/bin/bash
# Bootstrap the always-on Android WoL relay inside Termux.

set -Eeuo pipefail

log() { printf '[+] %s\n' "$*"; }
die() { printf '[-] %s\n' "$*" >&2; exit 1; }

command -v pkg >/dev/null 2>&1 \
    || die "Run this script inside the Termux app."

log "Updating Termux packages..."
pkg update -y
pkg upgrade -y
pkg install -y openssh wol

command -v termux-wake-lock >/dev/null 2>&1 \
    || die "termux-wake-lock is missing. Update Termux from F-Droid/GitHub and retry."

log "Creating the Termux:Boot startup script..."
mkdir -p "$HOME/.termux/boot" "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
cat > "$HOME/.termux/boot/10-pwnbox-relay" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
sshd
EOF
chmod 700 "$HOME/.termux/boot/10-pwnbox-relay"

log "Set a temporary Termux password for the first ssh-copy-id from the Mac."
log "After key authentication works, the README shows how to disable SSH password login."
passwd

termux-wake-lock
pkill -f '[s]shd' 2>/dev/null || true
sshd

TERMUX_USER=$(whoami)
log "Relay is ready."
printf '\nTermux user : %s\n' "$TERMUX_USER"
printf 'SSH port    : 8022\n'
printf 'Boot script : %s/.termux/boot/10-pwnbox-relay\n' "$HOME"
printf '\nFrom the Mac, run:\n'
printf '  ssh-copy-id -i ~/.ssh/pwnbox_android.pub -p 8022 %s@<android-tailscale-ip>\n' "$TERMUX_USER"
printf '\nTest Wake-on-LAN locally in Termux:\n'
printf '  wol <windows-ethernet-mac>\n'
