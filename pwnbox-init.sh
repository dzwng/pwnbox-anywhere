#!/bin/bash
# =============================================================================
# pwnbox-init.sh — Unified Kali Pwnbox Setup
# Combines: VNC (TigerVNC + XFCE), Guacamole (Docker), NoMachine, SSH
#           VMware Tools clipboard fix (DISPLAY :0 enforcement)
#
# Usage:
#   chmod +x pwnbox-init.sh
#   sudo ./pwnbox-init.sh
# =============================================================================

set -euo pipefail

# Detect the real user behind sudo — try multiple methods
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


# ──────────────────────────────────────────────
# CONFIGURATION — EDIT BEFORE RUNNING
# ──────────────────────────────────────────────
KALI_USER=$(_detect_user)
KALI_HOME="/home/$KALI_USER"
KALI_PASSWORD="kali"             # SSH login password (used by Guacamole SSH connection)
VNC_PASSWORD="kali1234"          # max 8 characters
VNC_RESOLUTION="1920x1080"
GUAC_USERNAME="kali"
GUAC_PASSWORD="kali"             # Guacamole web login password
GUAC_PORT="8080"
DOCKER_BRIDGE_IP="172.18.0.1"   # Docker bridge IP — Guacamole uses this to reach VNC/SSH on host
NX_PORT="4000"
NX_VERSION="9.4.14_1"           # Latest NoMachine stable version
NX_DEB="nomachine_${NX_VERSION}_amd64.deb"
NX_URL="https://download.nomachine.com/download/9.4/Linux/${NX_DEB}"
# ──────────────────────────────────────────────

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

[ "$EUID" -ne 0 ] && err "Run this script with sudo: sudo ./pwnbox-init.sh"

GUAC_DIR="$KALI_HOME/guacamole"

# =============================================================================
# DETECT ALREADY INSTALLED COMPONENTS
# =============================================================================
detect_installed() {
    INSTALLED_SSH=false
    INSTALLED_VNC=false
    INSTALLED_GUACAMOLE=false
    INSTALLED_NOMACHINE=false
    INSTALLED_VMTOOLS=false

    systemctl is-enabled ssh         &>/dev/null 2>&1 && INSTALLED_SSH=true       || true
    systemctl is-enabled vncserver@1 &>/dev/null 2>&1 && INSTALLED_VNC=true       || true
    { [ -d "$GUAC_DIR" ]             && INSTALLED_GUACAMOLE=true; }               || true
    { [ -f "/usr/NX/bin/nxserver" ]  && INSTALLED_NOMACHINE=true; }               || true
    { [ -f "$KALI_HOME/.local/bin/vmtoolsd-clipboard.sh" ] \
        && INSTALLED_VMTOOLS=true; }                                               || true
}

# =============================================================================
# MENU — SELECT OPTIONS TO INSTALL
# =============================================================================
show_menu() {
    detect_installed

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║           Pwnbox Setup — Component Select        ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    echo "  Currently installed:"
    $INSTALLED_SSH       && echo "    [✓] SSH"                         || echo "    [ ] SSH"
    $INSTALLED_VNC       && echo "    [✓] VNC"                         || echo "    [ ] VNC"
    $INSTALLED_GUACAMOLE && echo "    [✓] Guacamole"                   || echo "    [ ] Guacamole"
    $INSTALLED_NOMACHINE && echo "    [✓] NoMachine"                   || echo "    [ ] NoMachine"
    $INSTALLED_VMTOOLS   && echo "    [✓] VMware Clipboard Fix"        || echo "    [ ] VMware Clipboard Fix"
    echo ""
    echo "  Select components to install/reinstall."
    echo "  Enter numbers separated by spaces (e.g: 1 3)"
    echo "  Press Enter with no selection to cancel."
    echo ""
    echo "    1) SSH"
    echo "    2) VNC  (TigerVNC + XFCE — connect via any VNC client)"
    echo "    3) Guacamole  (Docker — browser-based, requires VNC)"
    echo "    4) NoMachine  (NX — best performance, attaches to display :0)"
    echo "    5) VMware Clipboard Fix  (enforce vmtoolsd on DISPLAY :0)"
    echo "    6) All of the above"
    echo ""
    read -rp "  Your choice: " MENU_INPUT
    echo ""

    INSTALL_SSH=false
    INSTALL_VNC=false
    INSTALL_GUACAMOLE=false
    INSTALL_NOMACHINE=false
    INSTALL_VMTOOLS=false

    [[ -z "$MENU_INPUT" ]] && { log "No selection made. Exiting."; exit 0; }

    for choice in $MENU_INPUT; do
        case "$choice" in
            1) INSTALL_SSH=true ;;
            2) INSTALL_VNC=true ;;
            3) INSTALL_GUACAMOLE=true; INSTALL_VNC=true ;;  # Guacamole needs VNC
            4) INSTALL_NOMACHINE=true ;;
            5) INSTALL_VMTOOLS=true ;;
            6) INSTALL_SSH=true; INSTALL_VNC=true; INSTALL_GUACAMOLE=true
               INSTALL_NOMACHINE=true; INSTALL_VMTOOLS=true ;;
            *) warn "Unknown option: $choice — skipped" ;;
        esac
    done

    echo "  Will install:"
    if $INSTALL_SSH;       then echo "    → SSH"; fi
    if $INSTALL_VNC;       then echo "    → VNC"; fi
    if $INSTALL_GUACAMOLE; then echo "    → Guacamole (includes VNC)"; fi
    if $INSTALL_NOMACHINE; then echo "    → NoMachine"; fi
    if $INSTALL_VMTOOLS;   then echo "    → VMware Clipboard Fix"; fi
    echo ""
    read -rp "  Confirm? (y/N): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && { log "Cancelled."; exit 0; }
}

# =============================================================================
# INSTALL: COMMON BASE PACKAGES
# =============================================================================
install_base_packages() {
    section "Base Packages"
    log "Updating package lists..."
    apt-get update

    local pkgs="curl net-tools"

    if $INSTALL_VNC;       then pkgs="$pkgs tigervnc-standalone-server xfce4 xfce4-goodies dbus-x11 xterm"; fi
    if $INSTALL_GUACAMOLE; then pkgs="$pkgs docker.io docker-compose"; fi
    if $INSTALL_NOMACHINE; then pkgs="$pkgs xfce4 xfce4-goodies dbus-x11 xterm wget pulseaudio"; fi
    if $INSTALL_SSH;       then pkgs="$pkgs openssh-server"; fi
    # open-vm-tools-desktop is required for clipboard support (GUI/vmusr plugin)
    if $INSTALL_VMTOOLS;   then pkgs="$pkgs open-vm-tools open-vm-tools-desktop"; fi

    log "Installing: $pkgs"
    # shellcheck disable=SC2086
    DEBIAN_FRONTEND=noninteractive apt-get install -y $pkgs 2>/dev/null || true
}

# =============================================================================
# INSTALL: SSH
# =============================================================================
install_ssh() {
    section "SSH"
    systemctl enable ssh --now
    systemctl is-active --quiet ssh \
        && log "SSH is running on port 22" \
        || warn "SSH may have issues — check: systemctl status ssh"
}

# =============================================================================
# INSTALL: VNC
# Note: called by both VNC-only and Guacamole paths; deduped via VNC_SETUP_DONE
# =============================================================================
VNC_SETUP_DONE=false

install_vnc() {
    if $VNC_SETUP_DONE; then
        log "VNC already configured in this run — skipping duplicate setup"
        return
    fi
    VNC_SETUP_DONE=true

    section "VNC (TigerVNC + XFCE)"

    # Kill existing session if any
    sudo -u "$KALI_USER" vncserver -kill :1 2>/dev/null || true
    sleep 1

    # VNC password (max 8 chars)
    mkdir -p "$KALI_HOME/.config/tigervnc"
    echo "$VNC_PASSWORD" | vncpasswd -f > "$KALI_HOME/.config/tigervnc/passwd"
    chmod 600 "$KALI_HOME/.config/tigervnc/passwd"
    chown "$KALI_USER:$KALI_USER" "$KALI_HOME/.config/tigervnc/passwd"

    # xstartup — launch XFCE
    mkdir -p "$KALI_HOME/.vnc"
    cat > "$KALI_HOME/.vnc/xstartup" << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
exec startxfce4
EOF
    chmod +x "$KALI_HOME/.vnc/xstartup"
    chown "$KALI_USER:$KALI_USER" "$KALI_HOME/.vnc/xstartup"

    # Systemd service template
    cat > /etc/systemd/system/vncserver@.service << EOF
[Unit]
Description=TigerVNC server (display :%i)
After=syslog.target network.target

[Service]
Type=forking
User=$KALI_USER
WorkingDirectory=$KALI_HOME
Environment="HOME=$KALI_HOME"
Environment="USER=$KALI_USER"
ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver :%i -depth 24 -xstartup $KALI_HOME/.vnc/xstartup -localhost no
ExecStop=/usr/bin/vncserver -kill :%i
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Override for :1 — set resolution
    mkdir -p /etc/systemd/system/vncserver@1.service.d
    cat > /etc/systemd/system/vncserver@1.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/bin/vncserver :1 -geometry ${VNC_RESOLUTION} -depth 24 -xstartup ${KALI_HOME}/.vnc/xstartup -localhost no
EOF

    systemctl daemon-reload
    systemctl enable vncserver@1 --now
    sleep 2

    if ss -tlnp | grep -q "5901"; then
        log "VNC :1 running on port 5901 (${VNC_RESOLUTION})"
    else
        warn "VNC :1 not detected — check: sudo systemctl status vncserver@1"
    fi
}

# =============================================================================
# INSTALL: DOCKER
# =============================================================================
install_docker() {
    section "Docker"
    systemctl enable docker --now
    usermod -aG docker "$KALI_USER"
    log "Docker enabled, $KALI_USER added to docker group"
}

# =============================================================================
# INSTALL: GUACAMOLE
# =============================================================================
install_guacamole() {
    section "Guacamole (Docker)"

    mkdir -p "$GUAC_DIR/guacamole-home"

    cat > "$GUAC_DIR/docker-compose.yml" << EOF
services:
  guacd:
    image: guacamole/guacd
    restart: unless-stopped

  guacamole:
    image: guacamole/guacamole
    restart: unless-stopped
    ports:
      - "${GUAC_PORT}:8080"
    environment:
      GUACD_HOSTNAME: guacd
      GUACAMOLE_HOME: /guacamole-home
    volumes:
      - ./guacamole-home:/guacamole-home
    depends_on:
      - guacd
EOF

    cat > "$GUAC_DIR/guacamole-home/user-mapping.xml" << EOF
<user-mapping>
  <authorize username="${GUAC_USERNAME}" password="${GUAC_PASSWORD}">
    <connection name="Kali Desktop (${VNC_RESOLUTION})">
      <protocol>vnc</protocol>
      <param name="hostname">${DOCKER_BRIDGE_IP}</param>
      <param name="port">5901</param>
      <param name="password">${VNC_PASSWORD}</param>
    </connection>
    <connection name="Kali SSH">
      <protocol>ssh</protocol>
      <param name="hostname">${DOCKER_BRIDGE_IP}</param>
      <param name="port">22</param>
      <param name="username">${KALI_USER}</param>
      <param name="password">${KALI_PASSWORD}</param>
    </connection>
  </authorize>
</user-mapping>
EOF

    chown -R "$KALI_USER:$KALI_USER" "$GUAC_DIR"

    cd "$GUAC_DIR"
    log "Pulling Docker images (may take a few minutes)..."
    sudo -u "$KALI_USER" docker compose pull
    log "Starting Guacamole..."
    sudo -u "$KALI_USER" docker compose up -d

    log "Waiting for Guacamole to be ready..."
    for i in $(seq 1 12); do
        if curl -sf "http://localhost:${GUAC_PORT}/guacamole/" > /dev/null 2>&1; then
            log "Guacamole is running and ready"
            break
        fi
        sleep 5
        [ "$i" -eq 12 ] && warn "Guacamole did not respond after 60s — check: cd ~/guacamole && docker compose logs"
    done
}

# =============================================================================
# INSTALL: NOMACHINE
# =============================================================================
install_nomachine() {
    section "NoMachine NX"

    NX_TARGET_VER=$(echo "$NX_VERSION" | grep -oP '^\d+\.\d+\.\d+')
    SKIP_NX_INSTALL=false

    if [ -f "/usr/NX/bin/nxserver" ]; then
        INSTALLED_VER=$(/usr/NX/bin/nxserver --version 2>/dev/null \
            | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
        if [ "$INSTALLED_VER" = "$NX_TARGET_VER" ]; then
            log "NoMachine $INSTALLED_VER already installed — skipping download"
            SKIP_NX_INSTALL=true
        else
            warn "NoMachine $INSTALLED_VER installed, target is $NX_TARGET_VER — reinstalling"
        fi
    fi

    if [ "$SKIP_NX_INSTALL" = false ]; then
        NX_TMPDIR=$(mktemp -d)
        trap "rm -rf $NX_TMPDIR" EXIT
        log "Downloading NoMachine ${NX_VERSION}..."
        wget -q --show-progress -O "$NX_TMPDIR/$NX_DEB" "$NX_URL" \
            || err "Download failed. Check URL: $NX_URL"
        log "Installing NoMachine package..."
        dpkg -i "$NX_TMPDIR/$NX_DEB" \
            || err "dpkg install failed"
        [ -f "/usr/NX/bin/nxserver" ] \
            || err "nxserver not found after install — something went wrong"
        log "NoMachine ${NX_VERSION} installed"
    fi

    # Configuration
    NX_CFG="/usr/NX/etc/server.cfg"
    [ -f "$NX_CFG" ] || err "NoMachine config not found at $NX_CFG"
    cp "$NX_CFG" "${NX_CFG}.bak"

    apply_nx_cfg() {
        local key="$1" value="$2"
        if grep -q "^$key " "$NX_CFG"; then
            sed -i "s|^$key .*|$key $value|" "$NX_CFG"
        else
            echo "$key $value" >> "$NX_CFG"
        fi
    }

    apply_nx_cfg "NXPort"                "$NX_PORT"
    apply_nx_cfg "DisplayBase"           "0"
    apply_nx_cfg "EnableShadowing"       "1"
    apply_nx_cfg "CreateDisplay"         "0"
    apply_nx_cfg "AudioInterface"        "pulseaudio"
    apply_nx_cfg "VirtualDesktopCommand" "startxfce4"
    log "NoMachine config applied (port $NX_PORT, display :0, PulseAudio)"

    # XFCE fallback session
    XSESSION="$KALI_HOME/.xsession"
    cat > "$XSESSION" << 'EOF'
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
pulseaudio --start --daemonize 2>/dev/null || true
exec startxfce4
EOF
    chmod +x "$XSESSION"
    chown "$KALI_USER:$KALI_USER" "$XSESSION"

    /usr/NX/bin/nxserver --restart 2>/dev/null || /usr/NX/bin/nxserver --start
    sleep 3

    if ss -tlnp | grep -q ":$NX_PORT" || /usr/NX/bin/nxserver --status 2>/dev/null | grep -qi "running\|started"; then
        log "NoMachine is running on port $NX_PORT"
    else
        warn "NoMachine may not be running — check: sudo /usr/NX/bin/nxserver --status"
    fi
}

# =============================================================================
# INSTALL: VMWARE TOOLS CLIPBOARD FIX
#
# Root cause: when VNC starts at boot via systemd, it claims DISPLAY :1.
# The open-vm-tools XFCE autostart then launches vmtoolsd -n vmusr attached
# to :1 instead of :0, breaking host ↔ VM clipboard sync.
#
# Fix: deploy a wrapper script that explicitly forces DISPLAY=:0, then
# register it as an XFCE autostart entry so it runs on every :0 login.
# The wrapper also kills any stale vmusr instance before starting fresh.
# =============================================================================
install_vmware_tools() {
    section "VMware Tools Clipboard Fix"

    # Ensure the desktop variant is installed — it carries the vmusr plugin
    # (open-vm-tools alone does NOT include clipboard support)
    if ! dpkg -l open-vm-tools-desktop &>/dev/null; then
        log "Installing open-vm-tools-desktop..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y open-vm-tools open-vm-tools-desktop 2>/dev/null \
            || warn "Could not install open-vm-tools-desktop — clipboard may not work"
    else
        log "open-vm-tools-desktop already installed"
    fi

    # Locate the vmusr plugin directory (path may differ across versions)
    VMUSR_PLUGIN_DIR=""
    for candidate in \
        /usr/lib/open-vm-tools/plugins/vmusr \
        /usr/lib/x86_64-linux-gnu/open-vm-tools/plugins/vmusr \
        /usr/lib/vmware-tools/plugins/vmusr; do
        if [ -d "$candidate" ]; then
            VMUSR_PLUGIN_DIR="$candidate"
            break
        fi
    done

    if [ -z "$VMUSR_PLUGIN_DIR" ]; then
        warn "vmusr plugin directory not found — skipping clipboard fix"
        warn "Check: find /usr/lib -name 'libvmtools*' -o -name 'vmusr' -type d 2>/dev/null"
        return
    fi
    log "vmusr plugin dir: $VMUSR_PLUGIN_DIR"

    # ── Wrapper script ────────────────────────────────────────────────────────
    # Runs as the normal user (not root). Forces DISPLAY=:0 so the vmusr
    # plugin registers with the physical X session, not the VNC session (:1).
    VMTOOLS_BIN_DIR="$KALI_HOME/.local/bin"
    VMTOOLS_SCRIPT="$VMTOOLS_BIN_DIR/vmtoolsd-clipboard.sh"

    mkdir -p "$VMTOOLS_BIN_DIR"
    cat > "$VMTOOLS_SCRIPT" << WRAPPER
#!/bin/bash
# vmtoolsd-clipboard.sh — enforce DISPLAY :0 for VMware clipboard sync
# Deployed by pwnbox-init.sh. Do not run as root.

# Kill any existing vmusr instance (may be attached to wrong display)
pkill -f "vmtoolsd -n vmusr" 2>/dev/null || true
sleep 1

# Start fresh on the physical display
exec /usr/bin/vmtoolsd -n vmusr
WRAPPER

    chmod +x "$VMTOOLS_SCRIPT"
    chown "$KALI_USER:$KALI_USER" "$VMTOOLS_SCRIPT"
    log "Wrapper script written: $VMTOOLS_SCRIPT"

    # ── XFCE autostart entry ─────────────────────────────────────────────────
    # Runs on every XFCE session login on display :0.
    # sleep 2 gives XFCE time to finish initialising before vmtoolsd attaches.
    AUTOSTART_DIR="$KALI_HOME/.config/autostart"
    AUTOSTART_FILE="$AUTOSTART_DIR/vmtoolsd-clipboard.desktop"

    mkdir -p "$AUTOSTART_DIR"
    cat > "$AUTOSTART_FILE" << DESKTOP
[Desktop Entry]
Type=Application
Name=VMware Clipboard Sync
Comment=Force vmtoolsd vmusr onto DISPLAY :0 for host<->VM clipboard
Exec=bash -c 'sleep 2 && DISPLAY=:0 ${VMTOOLS_SCRIPT}'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
DESKTOP

    chown -R "$KALI_USER:$KALI_USER" "$AUTOSTART_DIR"
    log "Autostart entry written: $AUTOSTART_FILE"

    # ── Apply immediately (best-effort, non-fatal) ────────────────────────────
    # Try to restart vmtoolsd vmusr right now on :0 so clipboard works without
    # needing a logout/login. This only succeeds if an X :0 session is active.
    log "Attempting to apply clipboard fix immediately..."
    if XAUTHORITY=$(sudo -u "$KALI_USER" bash -c \
            'ls /home/'"$KALI_USER"'/.Xauthority 2>/dev/null || \
             ls /tmp/.Xauthority-'"$KALI_USER"' 2>/dev/null || \
             ls /run/user/$(id -u '"$KALI_USER"')/.mutter-Xwaylandauth* 2>/dev/null | head -1' \
        2>/dev/null); then
        pkill -f "vmtoolsd -n vmusr" 2>/dev/null || true
        sleep 1
        sudo -u "$KALI_USER" env DISPLAY=:0 XAUTHORITY="$XAUTHORITY" \
            "$VMTOOLS_SCRIPT" >/dev/null 2>&1 &
        sleep 2
        # Verify the new process is on :0
        NEW_PID=$(pgrep -f "vmtoolsd -n vmusr" | head -1 || true)
        if [ -n "$NEW_PID" ]; then
            NEW_DISPLAY=$(cat /proc/"$NEW_PID"/environ 2>/dev/null \
                | tr '\0' '\n' | grep "^DISPLAY=" || true)
            if echo "$NEW_DISPLAY" | grep -q "^DISPLAY=:0"; then
                log "vmtoolsd -n vmusr is now running on DISPLAY=:0 (PID $NEW_PID)"
            else
                warn "vmtoolsd started but display may be wrong ($NEW_DISPLAY)"
                warn "Clipboard sync will be correct after next login"
            fi
        else
            warn "vmtoolsd -n vmusr did not start immediately"
            warn "Clipboard sync will be active after next login to display :0"
        fi
    else
        warn "No active X :0 session detected — clipboard fix will apply on next login"
    fi
}

# =============================================================================
# ALIASES
# =============================================================================
install_aliases() {
    section "Shell Aliases"

    local ALIASES=""

    if $INSTALL_VNC && ! $INSTALL_GUACAMOLE; then
        ALIASES+="
# VNC aliases
alias vncstart='vncserver :1 -geometry $VNC_RESOLUTION -depth 24 -xstartup $KALI_HOME/.vnc/xstartup -localhost no'
alias vncstop='vncserver -kill :1'
alias vncstatus='systemctl status vncserver@1 --no-pager'
alias vnc-log='journalctl -u vncserver@1 -f'
"
    fi

    if $INSTALL_GUACAMOLE; then
        ALIASES+="
# Self-hosted Pwnbox aliases
alias vncstart='vncserver :1 -geometry $VNC_RESOLUTION -depth 24 -xstartup $KALI_HOME/.vnc/xstartup -localhost no'
alias vncstop='vncserver -kill :1'
alias guac-start='cd $GUAC_DIR && docker compose up -d'
alias guac-stop='cd $GUAC_DIR && docker compose down'
alias guac-log='cd $GUAC_DIR && docker compose logs -f'
alias pwnbox-status='systemctl status vncserver@1 ssh docker --no-pager'
"
    fi

    if $INSTALL_NOMACHINE; then
        ALIASES+="
# NoMachine aliases
alias nx-status='/usr/NX/bin/nxserver --status'
alias nx-restart='sudo /usr/NX/bin/nxserver --restart'
alias nx-stop='sudo /usr/NX/bin/nxserver --stop'
alias nx-log='sudo tail -f /usr/NX/var/log/nxserver.log'
"
    fi

    if $INSTALL_VMTOOLS; then
        ALIASES+="
# VMware clipboard aliases
alias clipboard-fix='pkill -f \"vmtoolsd -n vmusr\" 2>/dev/null; sleep 1; DISPLAY=:0 $KALI_HOME/.local/bin/vmtoolsd-clipboard.sh &'
alias clipboard-status='VMPID=\$(pgrep -f \"vmtoolsd -n vmusr\"); [ -n \"\$VMPID\" ] && echo \"PID \$VMPID: \$(cat /proc/\$VMPID/environ 2>/dev/null | tr \"\\0\" \"\\n\" | grep DISPLAY)\" || echo \"vmtoolsd vmusr not running\"'
"
    fi

    [[ -z "$ALIASES" ]] && return

    for RC in "$KALI_HOME/.bashrc" "$KALI_HOME/.zshrc"; do
        [ -f "$RC" ] || continue
        # Avoid duplicate alias blocks
        if ! grep -q "VNC aliases\|Self-hosted Pwnbox aliases\|NoMachine aliases\|VMware clipboard aliases" "$RC"; then
            echo "$ALIASES" >> "$RC"
            log "Added aliases to $RC"
        else
            log "Aliases already present in $RC — skipped"
        fi
    done
}

# =============================================================================
# SUMMARY
# =============================================================================
print_summary() {
    section "Setup Complete"

    TAILSCALE_IP=$(ip addr show tailscale0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 || echo "(Tailscale not installed)")
    LOCAL_IP=$(ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 \
        || ip addr show ens33 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 \
        || ip route get 1 2>/dev/null | awk '{print $7; exit}' \
        || echo "N/A")

    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║              Pwnbox — Setup Summary              ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""

    if $INSTALL_SSH; then
        echo "  [SSH]"
        echo "    Port 22 — use your Kali username / password"
        echo ""
    fi

    if $INSTALL_VNC; then
        echo "  [VNC]"
        echo "    Local:     ${LOCAL_IP}:5901"
        echo "    Tailscale: ${TAILSCALE_IP}:5901"
        echo "    Password:  ${VNC_PASSWORD}  |  Resolution: ${VNC_RESOLUTION}"
        echo "    Connect:   RealVNC Viewer, TigerVNC Viewer, Remmina, etc."
        echo "    SSH tunnel: ssh -L 5901:localhost:5901 ${KALI_USER}@<host>"
        echo ""
    fi

    if $INSTALL_GUACAMOLE; then
        echo "  [Guacamole]"
        echo "    Local:     http://${LOCAL_IP}:${GUAC_PORT}/guacamole"
        echo "    Tailscale: http://${TAILSCALE_IP}:${GUAC_PORT}/guacamole"
        echo "    Login:     ${GUAC_USERNAME} / ${GUAC_PASSWORD}"
        echo "    Connections: Kali Desktop (VNC) + Kali SSH"
        echo ""
    fi

    if $INSTALL_NOMACHINE; then
        echo "  [NoMachine]"
        echo "    Local:     ${LOCAL_IP}:${NX_PORT}"
        echo "    Tailscale: ${TAILSCALE_IP}:${NX_PORT}"
        echo "    Login:     your Kali OS username / password"
        echo "    Protocol:  NX — attaches to display :0 (shared session)"
        echo "    Client:    https://www.nomachine.com/download"
        echo ""
    fi

    if $INSTALL_VMTOOLS; then
        echo "  [VMware Clipboard Fix]"
        echo "    Wrapper:   $KALI_HOME/.local/bin/vmtoolsd-clipboard.sh"
        echo "    Autostart: $KALI_HOME/.config/autostart/vmtoolsd-clipboard.desktop"
        echo "    Active on: DISPLAY :0 (physical VMware console)"
        echo "    Note:      Clipboard sync applies on next :0 login if not active now"
        echo ""
    fi

    echo "  Useful commands:"
    $INSTALL_VNC        && echo "    vncstatus / vncstart / vncstop"
    $INSTALL_GUACAMOLE  && echo "    guac-start / guac-stop / guac-log / pwnbox-status"
    $INSTALL_NOMACHINE  && echo "    nx-status / nx-restart / nx-log"
    $INSTALL_VMTOOLS    && echo "    clipboard-fix / clipboard-status"
    echo ""

    if [[ "$TAILSCALE_IP" == *"not installed"* ]]; then
        echo "  Tailscale not detected — to install:"
        echo "    curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up"
        echo ""
    fi
    echo "══════════════════════════════════════════════════"
}

# =============================================================================
# MAIN
# =============================================================================
show_menu || true

install_base_packages

if $INSTALL_SSH;       then install_ssh; fi
if $INSTALL_VNC;       then install_vnc; fi       # standalone VNC
if $INSTALL_GUACAMOLE; then install_docker; fi
if $INSTALL_GUACAMOLE; then install_vnc; fi       # VNC for Guacamole (deduped by VNC_SETUP_DONE flag)
if $INSTALL_GUACAMOLE; then install_guacamole; fi
if $INSTALL_NOMACHINE; then install_nomachine; fi
if $INSTALL_VMTOOLS;   then install_vmware_tools; fi

install_aliases
print_summary
