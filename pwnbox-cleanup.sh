#!/bin/bash
# =============================================================================
# pwnbox-cleanup.sh — Unified Cleanup
# Detects and selectively removes: SSH, VNC, Guacamole, NoMachine
#
# Usage:
#   chmod +x pwnbox-cleanup.sh
#   sudo ./pwnbox-cleanup.sh
# =============================================================================

set -eo pipefail  # -u removed: SUDO_USER may be unset on some sudo configs

_detect_user() {
    if [ -n "${SUDO_USER-}" ] && [ "${SUDO_USER}" != "root" ]; then
        echo "$SUDO_USER"; return
    fi
    local ln; ln=$(logname 2>/dev/null) \
        && [ -n "$ln" ] && [ "$ln" != "root" ] && { echo "$ln"; return; }
    local who; who=$(who am i 2>/dev/null | awk '{print $1}') \
        && [ -n "$who" ] && [ "$who" != "root" ] && { echo "$who"; return; }
    echo "kali"
}


KALI_USER=$(_detect_user)
KALI_HOME="/home/$KALI_USER"
GUAC_DIR="$KALI_HOME/guacamole"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}[+]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
err()     { echo -e "${RED}[-]${NC} $1"; exit 1; }
section() { echo -e "\n${CYAN}${BOLD}━━━ $1 ━━━${NC}"; }

[ "$EUID" -ne 0 ] && err "Run this script with sudo: sudo ./pwnbox-cleanup.sh"

# =============================================================================
# DETECT INSTALLED COMPONENTS
# =============================================================================
detect_installed() {
    INSTALLED_SSH=false
    INSTALLED_VNC=false
    INSTALLED_GUACAMOLE=false
    INSTALLED_NOMACHINE=false

    systemctl is-enabled ssh         &>/dev/null 2>&1 && INSTALLED_SSH=true        || true
    systemctl is-enabled vncserver@1 &>/dev/null 2>&1 && INSTALLED_VNC=true        || true
    { [ -d "$GUAC_DIR" ]           && INSTALLED_GUACAMOLE=true; } || true
    { [ -f "/usr/NX/bin/nxserver" ] && INSTALLED_NOMACHINE=true; } || true
}

# =============================================================================
# MENU — SELECT OPTIONS TO REMOVE
# =============================================================================
show_menu() {
    detect_installed

    if ! $INSTALLED_SSH && ! $INSTALLED_VNC && ! $INSTALLED_GUACAMOLE && ! $INSTALLED_NOMACHINE; then
        warn "Nothing installed detected. Exiting."
        exit 0
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║          Pwnbox Cleanup — Component Select       ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "  Currently installed:"
    $INSTALLED_SSH        && echo "    [✓] SSH"        || echo "    [ ] SSH         (not installed)"
    $INSTALLED_VNC        && echo "    [✓] VNC"        || echo "    [ ] VNC         (not installed)"
    $INSTALLED_GUACAMOLE  && echo "    [✓] Guacamole"  || echo "    [ ] Guacamole   (not installed)"
    $INSTALLED_NOMACHINE  && echo "    [✓] NoMachine"  || echo "    [ ] NoMachine   (not installed)"
    echo ""
    echo "  Select components to REMOVE."
    echo "  Enter numbers separated by spaces (e.g: 2 3)"
    echo "  Press Enter with no selection to cancel."
    echo ""
    $INSTALLED_SSH       && echo "    1) SSH"
    $INSTALLED_VNC       && echo "    2) VNC"
    $INSTALLED_GUACAMOLE && echo "    3) Guacamole  (removes Docker + containers)"
    $INSTALLED_NOMACHINE && echo "    4) NoMachine"
    echo "    5) All of the above (installed components only)"
    echo ""
    read -rp "  Your choice: " MENU_INPUT
    echo ""

    REMOVE_SSH=false
    REMOVE_VNC=false
    REMOVE_GUACAMOLE=false
    REMOVE_NOMACHINE=false

    [[ -z "$MENU_INPUT" ]] && { log "No selection made. Exiting."; exit 0; }

    for choice in $MENU_INPUT; do
        case "$choice" in
            1) $INSTALLED_SSH       && REMOVE_SSH=true       || warn "SSH not installed — skipped" ;;
            2) $INSTALLED_VNC       && REMOVE_VNC=true       || warn "VNC not installed — skipped" ;;
            3) $INSTALLED_GUACAMOLE && REMOVE_GUACAMOLE=true || warn "Guacamole not installed — skipped" ;;
            4) $INSTALLED_NOMACHINE && REMOVE_NOMACHINE=true || warn "NoMachine not installed — skipped" ;;
            5)
                $INSTALLED_SSH       && REMOVE_SSH=true
                $INSTALLED_VNC       && REMOVE_VNC=true
                $INSTALLED_GUACAMOLE && REMOVE_GUACAMOLE=true
                $INSTALLED_NOMACHINE && REMOVE_NOMACHINE=true
                ;;
            *) warn "Unknown option: $choice — skipped" ;;
        esac
    done

    # Dependency checks — handle both directions

    # Removing VNC but Guacamole still installed → Guacamole's VNC connection will break
    if $REMOVE_VNC && ! $REMOVE_GUACAMOLE && $INSTALLED_GUACAMOLE; then
        echo ""
        warn "Guacamole depends on VNC (port 5901). Removing VNC will break the Kali Desktop connection in Guacamole."
        read -rp "  Remove Guacamole as well? (y/N): " GUAC_CONFIRM
        [[ "$GUAC_CONFIRM" == "y" || "$GUAC_CONFIRM" == "Y" ]] && REMOVE_GUACAMOLE=true
    fi

    # Removing Guacamole but not VNC — VNC can stay, it works standalone
    if $REMOVE_GUACAMOLE && ! $REMOVE_VNC && $INSTALLED_VNC; then
        echo ""
        read -rp "  Remove VNC as well? (VNC can still work standalone without Guacamole) (y/N): " VNC_CONFIRM
        [[ "$VNC_CONFIRM" == "y" || "$VNC_CONFIRM" == "Y" ]] && REMOVE_VNC=true
    fi

    echo ""
    echo "  Will remove:"
    $REMOVE_SSH        && echo "    → SSH"
    $REMOVE_VNC        && echo "    → VNC"
    $REMOVE_GUACAMOLE  && echo "    → Guacamole (Docker)"
    $REMOVE_NOMACHINE  && echo "    → NoMachine"
    echo ""
    warn "This is IRREVERSIBLE. Configuration files will be deleted."
    read -rp "  Confirm? (y/N): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { log "Cancelled."; exit 0; }
}

# =============================================================================
# REMOVE ALIAS BLOCK HELPER
# Removes a comment-header-delimited alias block from a shell RC file.
# Block is identified by its header comment; ends at the first blank line
# after block content has started.
# =============================================================================
remove_alias_block() {
    local path="$1"
    local header="$2"

    python3 - "$path" "$header" << 'PYEOF'
import sys

path   = sys.argv[1]
header = sys.argv[2]

with open(path, 'r') as f:
    lines = f.readlines()

out      = []
skip     = False
in_block = False

for line in lines:
    stripped = line.strip()

    if not skip and stripped == header:
        skip     = True
        in_block = False
        continue

    if not skip:
        out.append(line)
        continue

    if stripped == '':
        if in_block:
            skip     = False
            in_block = False
        continue

    in_block = True

while out and out[-1].strip() == '':
    out.pop()
out.append('\n')

with open(path, 'w') as f:
    f.writelines(out)
PYEOF
}

# =============================================================================
# CLEANUP: GUACAMOLE
# =============================================================================
cleanup_guacamole() {
    section "Removing Guacamole"

    if [ -d "$GUAC_DIR" ]; then
        cd "$GUAC_DIR"
        sudo -u "$KALI_USER" docker compose down --rmi all --volumes 2>/dev/null || true
        log "Guacamole containers, images, and volumes removed"
    fi

    rm -rf "$GUAC_DIR"
    log "Deleted ~/guacamole"

    log "Removing Docker packages..."
    apt-get remove -y --purge docker.io docker-compose 2>/dev/null || true
    rm -f /etc/docker/daemon.json
}

# =============================================================================
# CLEANUP: VNC
# =============================================================================
cleanup_vnc() {
    section "Removing VNC"

    sudo -u "$KALI_USER" vncserver -kill :1 2>/dev/null || true
    sudo -u "$KALI_USER" vncserver -kill :2 2>/dev/null || true

    systemctl stop    vncserver@1 2>/dev/null || true
    systemctl stop    vncserver@2 2>/dev/null || true
    systemctl disable vncserver@1 2>/dev/null || true
    systemctl disable vncserver@2 2>/dev/null || true

    rm -f  /etc/systemd/system/vncserver@.service
    rm -rf /etc/systemd/system/vncserver@1.service.d
    rm -rf /etc/systemd/system/vncserver@2.service.d

    systemctl daemon-reload
    log "VNC systemd services removed"

    rm -rf "$KALI_HOME/.vnc"
    rm -rf "$KALI_HOME/.config/tigervnc"
    log "Deleted ~/.vnc and ~/.config/tigervnc"

    apt-get remove -y --purge tigervnc-standalone-server xterm 2>/dev/null || true
}

# =============================================================================
# CLEANUP: NOMACHINE
# =============================================================================
cleanup_nomachine() {
    section "Removing NoMachine"

    /usr/NX/bin/nxserver --stop 2>/dev/null || true

    if [ -f "/usr/NX/scripts/setup/nxserver" ]; then
        /usr/NX/scripts/setup/nxserver --uninstall 2>/dev/null || true
    else
        dpkg --purge nomachine 2>/dev/null || true
    fi

    rm -rf /usr/NX
    log "NoMachine removed"

    rm -f "$KALI_HOME/.xsession"
    log "Deleted ~/.xsession"
}

# =============================================================================
# CLEANUP: SSH
# Intentionally light-touch: disable + purge openssh-server,
# but don't touch /etc/ssh in case user has custom config.
# =============================================================================
cleanup_ssh() {
    section "Removing SSH"
    systemctl stop    ssh 2>/dev/null || true
    systemctl disable ssh 2>/dev/null || true
    apt-get remove -y --purge openssh-server 2>/dev/null || true
    log "SSH removed"
}

# =============================================================================
# CLEANUP: ALIASES
# =============================================================================
cleanup_aliases() {
    section "Removing Shell Aliases"

    for RC in "$KALI_HOME/.bashrc" "$KALI_HOME/.zshrc"; do
        [ -f "$RC" ] || continue
        CHANGED=false

        if $REMOVE_SSH; then
            : # SSH installs no aliases
        fi

        if $REMOVE_VNC && ! $REMOVE_GUACAMOLE; then
            if grep -q "^# VNC aliases$" "$RC"; then
                remove_alias_block "$RC" "# VNC aliases"
                log "Removed VNC aliases from $RC"
                CHANGED=true
            fi
        fi

        if $REMOVE_GUACAMOLE; then
            if grep -q "^# Self-hosted Pwnbox aliases$" "$RC"; then
                remove_alias_block "$RC" "# Self-hosted Pwnbox aliases"
                log "Removed Pwnbox aliases from $RC"
                CHANGED=true
            fi
            # Also clean up VNC aliases if they exist alongside Guacamole ones
            if grep -q "^# VNC aliases$" "$RC"; then
                remove_alias_block "$RC" "# VNC aliases"
                log "Removed VNC aliases from $RC"
                CHANGED=true
            fi
        fi

        if $REMOVE_NOMACHINE; then
            if grep -q "^# NoMachine aliases$" "$RC"; then
                remove_alias_block "$RC" "# NoMachine aliases"
                log "Removed NoMachine aliases from $RC"
                CHANGED=true
            fi
        fi

        $CHANGED || log "No matching aliases in $RC — skipped"
    done
}

# =============================================================================
# MAIN
# =============================================================================
show_menu || true

if $REMOVE_GUACAMOLE; then cleanup_guacamole || true; fi
if $REMOVE_VNC;       then cleanup_vnc       || true; fi
if $REMOVE_NOMACHINE; then cleanup_nomachine || true; fi
if $REMOVE_SSH;       then cleanup_ssh       || true; fi

cleanup_aliases || true

section "Autoremove"
apt-get autoremove -y --purge 2>/dev/null || true

section "Cleanup Complete"
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║             Pwnbox — Cleanup Summary             ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
$REMOVE_SSH        && echo "  [✓] SSH removed"
$REMOVE_VNC        && echo "  [✓] VNC removed"
$REMOVE_GUACAMOLE  && echo "  [✓] Guacamole (Docker) removed"
$REMOVE_NOMACHINE  && echo "  [✓] NoMachine removed"
echo ""
echo "  To reinstall: sudo ./pwnbox-init.sh"
echo ""
echo "══════════════════════════════════════════════════"