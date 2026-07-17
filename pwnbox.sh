#!/usr/bin/env bash
# Configure SSH and on-demand TigerVNC on a clean Kali VMware guest.

set -Eeuo pipefail

PROGRAM="${0##*/}"
INSTALL_PATH="/usr/local/bin/pwnbox"
DISPLAY_NUMBER=1
VNC_PORT=$((5900 + DISPLAY_NUMBER))
DEFAULT_RESOLUTION="1920x1080"
AUTLOGIN_CONFIG="/etc/lightdm/lightdm.conf.d/50-pwnbox-autologin.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { printf "${GREEN}[+]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[!]${NC} %s\n" "$*" >&2; }
die() { printf "${RED}[-]${NC} %s\n" "$*" >&2; exit 1; }
section() { printf "\n${CYAN}--- %s ---${NC}\n" "$*"; }

usage() {
    cat <<EOF
Usage:
  sudo ./${PROGRAM} install [--enable-autologin] [--reset-vnc-password]
  sudo ./${PROGRAM} uninstall <vnc|autologin|all> [--yes]
  ${PROGRAM} status
  ${PROGRAM} vnc <start|stop|restart|status>

Environment variables for unattended install:
  VNC_PASSWORD             TigerVNC password (6-8 characters)
  VNC_RESOLUTION           Desktop size (default: ${DEFAULT_RESOLUTION})
  PWNBOX_SKIP_APT_UPDATE=1 Skip apt-get update
EOF
}

require_root() {
    [ "${EUID}" -eq 0 ] || die "Run this command with sudo."
}

detect_target_user() {
    if [ "${EUID}" -ne 0 ]; then
        id -un
        return
    fi
    if [ -n "${SUDO_USER-}" ] && [ "$SUDO_USER" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
        return
    fi
    die "Cannot determine the Kali user. Run with sudo from that user's shell."
}

init_user_paths() {
    TARGET_USER=$(detect_target_user)
    TARGET_UID=$(id -u "$TARGET_USER")
    TARGET_GID=$(id -g "$TARGET_USER")
    if [ "${EUID}" -ne 0 ]; then
        TARGET_HOME="$HOME"
    else
        TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
    fi
    [ -n "$TARGET_HOME" ] && [ -d "$TARGET_HOME" ] \
        || die "Home directory for $TARGET_USER was not found."

    PWNBOX_CONFIG_DIR="$TARGET_HOME/.config/pwnbox"
    PWNBOX_CONFIG="$PWNBOX_CONFIG_DIR/config"
    MANAGED_PACKAGES_FILE="$PWNBOX_CONFIG_DIR/managed-packages"
    VNC_PASSWORD_FILE="$PWNBOX_CONFIG_DIR/passwd"
    VNC_STARTUP="$PWNBOX_CONFIG_DIR/xstartup"
}

run_as_target() {
    if [ "${EUID}" -eq 0 ]; then
        runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" USER="$TARGET_USER" "$@"
    else
        "$@"
    fi
}

find_vncserver() {
    command -v vncserver 2>/dev/null || command -v tigervncserver 2>/dev/null
}

find_vncpasswd() {
    command -v vncpasswd 2>/dev/null || command -v tigervncpasswd 2>/dev/null
}

read_resolution() {
    local value="$DEFAULT_RESOLUTION"
    if [ -n "${VNC_RESOLUTION-}" ]; then
        value="$VNC_RESOLUTION"
    elif [ -f "$PWNBOX_CONFIG" ]; then
        value=$(awk -F= '$1 == "VNC_RESOLUTION" { print $2; exit }' "$PWNBOX_CONFIG")
        value="${value:-$DEFAULT_RESOLUTION}"
    fi
    [[ "$value" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]] \
        || die "Invalid VNC resolution: $value (expected WIDTHxHEIGHT)."
    printf '%s\n' "$value"
}

write_vnc_config() {
    local resolution
    resolution=$(read_resolution)
    install -d -m 0700 -o "$TARGET_USER" -g "$TARGET_GID" "$PWNBOX_CONFIG_DIR"
    printf 'VNC_RESOLUTION=%s\n' "$resolution" > "$PWNBOX_CONFIG"
    cat > "$VNC_STARTUP" <<'EOF'
#!/usr/bin/env bash
# Managed by Pwnbox Anywhere.
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_DESKTOP=xfce
# Bridge the clipboard between the VNC viewer and this session so copy/paste
# keeps working across vnc stop/start cycles.
vncconfig -nowin &
exec dbus-launch --exit-with-session startxfce4
EOF
    chown "$TARGET_USER:$TARGET_GID" "$PWNBOX_CONFIG" "$VNC_STARTUP"
    chmod 0600 "$PWNBOX_CONFIG"
    chmod 0700 "$VNC_STARTUP"
}

configure_vnc_password() {
    local reset_password="$1"
    local password="${VNC_PASSWORD-}"
    local passwd_command

    if [ -s "$VNC_PASSWORD_FILE" ] && [ "$reset_password" != "true" ] \
        && [ -z "$password" ]; then
        if [ -t 0 ]; then
            local answer
            read -rp "A VNC password already exists. Change it? [y/N]: " answer
            case "$answer" in
                [Yy]*) : ;;   # fall through and set a new password
                *) log "Keeping the existing VNC password."; return ;;
            esac
        else
            log "Keeping the existing VNC password."
            return
        fi
    fi
    if [ -z "$password" ]; then
        [ -t 0 ] || die "Set VNC_PASSWORD for a non-interactive install."
        while :; do
            read -rsp "VNC password (6-8 characters): " password
            printf '\n'
            if [ "${#password}" -ge 6 ] && [ "${#password}" -le 8 ]; then
                break
            fi
            warn "TigerVNC uses only 6-8 characters; please try again."
        done
    fi
    [ "${#password}" -ge 6 ] && [ "${#password}" -le 8 ] \
        || die "VNC_PASSWORD must contain 6-8 characters."

    passwd_command=$(find_vncpasswd) || die "TigerVNC password utility was not found."
    printf '%s\n' "$password" | "$passwd_command" -f > "$VNC_PASSWORD_FILE"
    chown "$TARGET_USER:$TARGET_GID" "$VNC_PASSWORD_FILE"
    chmod 0600 "$VNC_PASSWORD_FILE"
}

configure_autologin() {
    command -v lightdm >/dev/null 2>&1 \
        || die "LightDM is not installed; cannot enable graphical autologin."
    install -d -m 0755 /etc/lightdm/lightdm.conf.d
    cat > "$AUTLOGIN_CONFIG" <<EOF
[Seat:*]
autologin-user=$TARGET_USER
autologin-user-timeout=0
EOF
    chmod 0644 "$AUTLOGIN_CONFIG"
    log "LightDM autologin enabled for $TARGET_USER."
}

install_packages() {
    local enable_autologin="$1"
    PWNBOX_ADDED_TIGERVNC=false
    if ! dpkg-query -W -f='${Status}' tigervnc-standalone-server 2>/dev/null \
        | grep -q '^install ok installed$'; then
        PWNBOX_ADDED_TIGERVNC=true
    fi
    local packages=(
        openssh-server
        tigervnc-standalone-server
        dbus-x11
        open-vm-tools
        open-vm-tools-desktop
    )
    if ! command -v startxfce4 >/dev/null 2>&1; then
        packages+=(xfce4)
    fi
    if [ "$enable_autologin" = "true" ] && ! command -v lightdm >/dev/null 2>&1; then
        packages+=(lightdm)
    fi
    if [ "${PWNBOX_SKIP_APT_UPDATE-0}" != "1" ]; then
        log "Refreshing apt package metadata..."
        apt-get update
    fi
    log "Installing: ${packages[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
}

record_managed_packages() {
    if $PWNBOX_ADDED_TIGERVNC; then
        printf 'tigervnc-standalone-server\n' > "$MANAGED_PACKAGES_FILE"
        chown "$TARGET_USER:$TARGET_GID" "$MANAGED_PACKAGES_FILE"
        chmod 0600 "$MANAGED_PACKAGES_FILE"
    fi
}

install_command() {
    require_root
    init_user_paths
    local reset_password=false enable_autologin=false

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --reset-vnc-password) reset_password=true ;;
            --enable-autologin) enable_autologin=true ;;
            *) die "Unknown install option: $1" ;;
        esac
        shift
    done

    section "Install"
    install_packages "$enable_autologin"
    systemctl enable --now ssh
    systemctl enable --now open-vm-tools 2>/dev/null || true
    write_vnc_config
    record_managed_packages
    configure_vnc_password "$reset_password"
    $enable_autologin && configure_autologin

    if [ "$(readlink -f "$0")" != "$INSTALL_PATH" ]; then
        install -m 0755 "$0" "$INSTALL_PATH"
    fi

    log "SSH and on-demand TigerVNC are ready."
    printf '\nSSH:      ssh %s@<kali-tailscale-ip>\n' "$TARGET_USER"
    printf 'VNC:      pwnbox vnc start\n'
    printf 'VNC tunnel from Mac: ssh -N -L %s:127.0.0.1:%s pwnbox-kali\n' \
        "$VNC_PORT" "$VNC_PORT"
    $enable_autologin && printf 'Autologin will apply after the next reboot.\n'
}

vnc_start() {
    local resolution server
    resolution=$(read_resolution)
    server=$(find_vncserver) || die "TigerVNC is not installed. Run: sudo $PROGRAM install"
    [ -s "$VNC_PASSWORD_FILE" ] || die "VNC password is missing. Run: sudo $PROGRAM install"
    [ -x "$VNC_STARTUP" ] || die "VNC startup file is missing. Run: sudo $PROGRAM install"

    if run_as_target "$server" -list 2>/dev/null \
        | grep -qE "(^|[[:space:]]):${DISPLAY_NUMBER}([[:space:]]|$)"; then
        log "VNC display :${DISPLAY_NUMBER} is already running."
        return
    fi
    run_as_target "$server" ":${DISPLAY_NUMBER}" \
        -geometry "$resolution" \
        -depth 24 \
        -localhost yes \
        -PasswordFile "$VNC_PASSWORD_FILE" \
        -xstartup "$VNC_STARTUP"
    log "VNC started on 127.0.0.1:${VNC_PORT} (${resolution})."
}

vnc_stop() {
    local server
    if ! server=$(find_vncserver); then
        warn "TigerVNC is not installed."
        return
    fi
    run_as_target "$server" -kill ":${DISPLAY_NUMBER}" >/dev/null 2>&1 \
        && log "VNC display :${DISPLAY_NUMBER} stopped." \
        || warn "VNC display :${DISPLAY_NUMBER} was not running."

    # -kill returns before Xtigervnc has fully exited. Wait for the process to
    # die, then clear any stale lock/socket/pid so an immediate restart can
    # rebind :DISPLAY_NUMBER instead of hitting "already running" or a lock.
    local waited=0
    while pgrep -u "$TARGET_UID" -f "Xtigervnc.*:${DISPLAY_NUMBER}" >/dev/null 2>&1; do
        [ "$waited" -ge 20 ] && break
        sleep 0.5
        waited=$((waited + 1))
    done
    rm -f "/tmp/.X${DISPLAY_NUMBER}-lock" \
          "/tmp/.X11-unix/X${DISPLAY_NUMBER}" \
          "$TARGET_HOME/.vnc/"*":${DISPLAY_NUMBER}.pid" 2>/dev/null || true
}

vnc_status() {
    local server
    section "VNC"
    if server=$(find_vncserver); then
        run_as_target "$server" -list 2>/dev/null || true
    else
        warn "TigerVNC is not installed."
    fi
    if command -v ss >/dev/null 2>&1 \
        && ss -ltn | grep -qE "127\.0\.0\.1:${VNC_PORT}([[:space:]]|$)"; then
        log "Port ${VNC_PORT} is listening only on localhost."
    fi
}

vnc_command() {
    init_user_paths
    [ "$#" -eq 1 ] || die "Usage: $PROGRAM vnc <start|stop|restart|status>"
    case "$1" in
        start) vnc_start ;;
        stop) vnc_stop ;;
        restart) vnc_stop; vnc_start ;;
        status) vnc_status ;;
        *) die "Usage: $PROGRAM vnc <start|stop|restart|status>" ;;
    esac
}

service_state() {
    local service="$1"
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        printf 'running'
    elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
        printf 'enabled, stopped'
    else
        printf 'not enabled'
    fi
}

status_command() {
    init_user_paths
    local tailscale_ip="not detected"
    if command -v tailscale >/dev/null 2>&1; then
        tailscale_ip=$(tailscale ip -4 2>/dev/null | head -n1 || true)
        tailscale_ip="${tailscale_ip:-not connected}"
    fi

    section "Pwnbox status"
    printf 'User:       %s\n' "$TARGET_USER"
    printf 'Tailscale:  %s\n' "$tailscale_ip"
    printf 'SSH:        %s\n' "$(service_state ssh)"
    if [ -f "$AUTLOGIN_CONFIG" ]; then
        printf 'Autologin:  enabled for %s\n' "$TARGET_USER"
    else
        printf 'Autologin:  not managed by pwnbox\n'
    fi
    if pgrep -u "$TARGET_UID" -f "Xtigervnc.*:${DISPLAY_NUMBER}" >/dev/null 2>&1; then
        printf 'VNC:        running on localhost:%s\n' "$VNC_PORT"
    else
        printf 'VNC:        stopped (on demand)\n'
    fi
}

confirm_destructive() {
    local prompt="$1" assume_yes="$2"
    [ "$assume_yes" = "true" ] && return
    [ -t 0 ] || die "Interactive confirmation required (or pass --yes)."
    read -rp "$prompt [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Cancelled."
}

remove_vnc() {
    local remove_package=false
    if [ -f "$MANAGED_PACKAGES_FILE" ] \
        && grep -qx 'tigervnc-standalone-server' "$MANAGED_PACKAGES_FILE"; then
        remove_package=true
    fi
    vnc_stop || true
    rm -rf "$PWNBOX_CONFIG_DIR"
    if $remove_package; then
        apt-get remove -y --purge tigervnc-standalone-server
        log "Removed TigerVNC because it was installed by Pwnbox."
    else
        log "TigerVNC package was kept because Pwnbox did not record installing it."
    fi
    log "Pwnbox VNC configuration was removed."
}

uninstall_command() {
    require_root
    init_user_paths
    local assume_yes=false
    local targets=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --yes|-y) assume_yes=true ;;
            vnc|autologin|all) targets+=("$1") ;;
            *) die "Unknown uninstall target: $1" ;;
        esac
        shift
    done
    [ "${#targets[@]}" -gt 0 ] \
        || die "Choose what to remove: vnc, autologin, or all."
    confirm_destructive \
        "Remove Pwnbox-managed components: ${targets[*]}?" \
        "$assume_yes"

    local remove_vnc_flag=false remove_autologin=false target
    for target in "${targets[@]}"; do
        case "$target" in
            vnc) remove_vnc_flag=true ;;
            autologin) remove_autologin=true ;;
            all) remove_vnc_flag=true; remove_autologin=true ;;
        esac
    done

    $remove_vnc_flag && remove_vnc
    if $remove_autologin; then
        rm -f "$AUTLOGIN_CONFIG"
        log "Pwnbox LightDM autologin configuration removed."
    fi
    if $remove_vnc_flag && $remove_autologin; then
        rm -f "$INSTALL_PATH"
    fi
    log "SSH, VMware Tools, XFCE, LightDM, and other base packages were left untouched."
    log "Uninstall complete."
}

main() {
    case "${1-}" in
        install) shift; install_command "$@" ;;
        uninstall) shift; uninstall_command "$@" ;;
        status) shift; [ "$#" -eq 0 ] || die "Usage: $PROGRAM status"; status_command ;;
        vnc) shift; vnc_command "$@" ;;
        help|-h|--help|'') usage ;;
        *) die "Unknown command: $1 (try: $PROGRAM help)" ;;
    esac
}

main "$@"
