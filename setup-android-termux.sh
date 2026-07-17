#!/data/data/com.termux/files/usr/bin/bash
# Bootstrap or remove the always-on Android WoL relay inside Termux.

set -Eeuo pipefail

BOOT_SCRIPT="$HOME/.termux/boot/10-pwnbox-relay"
AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf '[-] %s\n' "$*" >&2; exit 1; }

command -v pkg >/dev/null 2>&1 || die "Run this script inside the Termux app."

usage() {
    cat <<EOF
Usage:
  $(basename "$0") [install] [--set-password] [--restart-sshd]
  $(basename "$0") uninstall [--stop-sshd] [--remove-packages]

install (default): install openssh + wol, create the Termux:Boot relay, hold a
  wake lock, and start sshd if it is not already running. Safe to re-run.
  --set-password     run 'passwd' (only needed before the first ssh-copy-id).
  --restart-sshd     restart a running sshd; drops the current SSH session.

uninstall: remove the boot script and release the wake lock so the relay no
  longer starts on boot. Keeps openssh/wol and Tailscale by default.
  --stop-sshd        also kill the running sshd; drops the current SSH session.
  --remove-packages  also 'pkg uninstall' openssh and wol (removes SSH access).
EOF
}

do_install() {
    local set_password="$1" restart_sshd="$2"

    log "Refreshing package metadata and ensuring openssh + wol..."
    pkg update -y
    pkg install -y openssh wol

    command -v termux-wake-lock >/dev/null 2>&1 \
        || die "termux-wake-lock is missing. Update Termux from F-Droid/GitHub and retry."

    log "Creating the Termux:Boot startup script..."
    mkdir -p "$HOME/.termux/boot" "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    cat > "$BOOT_SCRIPT" <<'EOF'
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
sshd
EOF
    chmod 700 "$BOOT_SCRIPT"

    # Only prompt for a password when explicitly asked, or on a first run where
    # no SSH key exists yet. Re-runs with a key already installed skip this.
    if [ "$set_password" = "true" ]; then
        log "Setting a Termux password (--set-password)."
        passwd
    elif [ ! -s "$AUTHORIZED_KEYS" ]; then
        log "No SSH key installed yet — set a temporary Termux password for the first ssh-copy-id."
        passwd
    else
        log "SSH key already present; keeping the current password (use --set-password to change it)."
    fi

    termux-wake-lock
    if [ "$restart_sshd" = "true" ]; then
        pkill -f '[s]shd' 2>/dev/null || true
        sshd
        log "Restarted sshd on port 8022."
    else
        # Harmless no-op if sshd is already bound to 8022; starts it otherwise.
        sshd 2>/dev/null || true
        log "sshd is up on port 8022 (started it if it was not already running)."
    fi

    local termux_user
    termux_user=$(whoami)
    log "Relay is ready."
    printf '\nTermux user : %s\n' "$termux_user"
    printf 'SSH port    : 8022\n'
    printf 'Boot script : %s\n' "$BOOT_SCRIPT"
    if [ ! -s "$AUTHORIZED_KEYS" ]; then
        printf '\nFrom the Mac, install the key:\n'
        printf '  ssh-copy-id -i ~/.ssh/pwnbox_android.pub -p 8022 %s@<android-tailscale-ip>\n' "$termux_user"
    fi
    printf '\nTest Wake-on-LAN locally in Termux:\n'
    printf '  wol <windows-ethernet-mac>\n'
}

do_uninstall() {
    local stop_sshd="$1" remove_packages="$2"

    if [ -f "$BOOT_SCRIPT" ]; then
        rm -f "$BOOT_SCRIPT"
        log "Removed the Termux:Boot relay script; sshd will not start on boot anymore."
    else
        log "Boot script not found (already removed)."
    fi

    termux-wake-unlock 2>/dev/null || true
    log "Released the wake lock."

    if [ "$stop_sshd" = "true" ]; then
        warn "Stopping sshd now — an active SSH session to this device will drop."
        pkill -f '[s]shd' 2>/dev/null || true
        log "sshd stopped."
    else
        log "Left the running sshd alone (pass --stop-sshd to kill it; it stays until reboot or manual kill)."
    fi

    if [ "$remove_packages" = "true" ]; then
        warn "Removing openssh and wol — you will lose SSH access to this device."
        pkg uninstall -y openssh wol || true
        log "Removed openssh and wol."
    else
        log "Kept openssh and wol (pass --remove-packages to remove them)."
    fi

    log "Uninstall complete. Tailscale and the Termux password were not touched."
}

action="install"
set_password="false"
restart_sshd="false"
stop_sshd="false"
remove_packages="false"

case "${1-}" in
    install)   action="install"; shift ;;
    uninstall) action="uninstall"; shift ;;
    -h|--help) usage; exit 0 ;;
esac

while [ "$#" -gt 0 ]; do
    case "$1" in
        --set-password)    set_password="true" ;;
        --restart-sshd)    restart_sshd="true" ;;
        --stop-sshd)       stop_sshd="true" ;;
        --remove-packages) remove_packages="true" ;;
        -h|--help)         usage; exit 0 ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
    shift
done

if [ "$action" = "uninstall" ]; then
    do_uninstall "$stop_sshd" "$remove_packages"
else
    do_install "$set_password" "$restart_sshd"
fi
