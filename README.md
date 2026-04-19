# 🐉 Pwnbox Anywhere

> Self-hosted Pwnbox on a Kali VM (VMware / Windows 11) — remote access via SSH, VNC, browser, or NoMachine over Tailscale.

Work from a café, travel the world, or commute lightly. Bring any device (MacBook, ThinkPad, or even a tablet) and instantly drop back into your heavy-duty, always-on Kali environment at home

---

## Overview

This repo provides two scripts that set up and tear down a self-hosted remote Kali desktop on a VMware VM running on Windows 11. Remote access is brokered over **Tailscale**, so no port forwarding or public IP is required.

| Script | Purpose |
|---|---|
| `pwnbox-init.sh` | Install and configure remote access components |
| `pwnbox-cleanup.sh` | Selectively remove installed components |

### Access Methods

| Method | Protocol | Port | Best For |
|---|---|---|---|
| **SSH** | SSH | 22 | Quick terminal access & port tunneling |
| **VNC** | RFB | 5901 | Traditional lightweight desktop (TigerVNC, Remmina) |
| **Guacamole** | HTTP | 8080 | Clientless browser-based desktop |
| **NoMachine** | NX | 4000 | High-performance, low-latency access to the live display |

---

## Architecture

```
[ Home ]                                [ Remote ]
┌──────────────────────────┐            ┌───────────────────┐
│  Windows 11 Host         │            │  MacBook / ThinkPad│
│  └─ VMware               │            │                   │
│     └─ Kali Linux VM     │◄─Tailscale─┤  SSH / VNC /      │
│        ├─ SSH (:22)      │            │  Browser /        │
│        ├─ VNC (:5901)    │            │  NoMachine client │
│        ├─ Guacamole (:8080)           │  Any browser      │
│        └─ NoMachine (:4000)           └───────────────────┘
└──────────────────────────┘
```

Tailscale handles NAT traversal — your Kali VM gets a stable private IP accessible from anywhere on your tailnet, with no public exposure.

---

## Prerequisites

- **Kali Linux VM** running in VMware on Windows 11
- **Tailscale** installed and authenticated on both the VM and your remote device

Install Tailscale on the VM if not already done:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

---

## Installation

```bash
git clone https://github.com/dzwng/pwnbox-anywhere.git
cd pwnbox-anywhere
chmod +x pwnbox-init.sh pwnbox-cleanup.sh
sudo ./pwnbox-init.sh
```

The script presents an interactive menu — select which components to install:

```
╔══════════════════════════════════════════════════╗
║           Pwnbox Setup — Component Select        ║
╚══════════════════════════════════════════════════╝

  1) SSH
  2) VNC  (TigerVNC + XFCE)
  3) Guacamole  (Docker — browser-based, requires VNC)
  4) NoMachine  (NX — best performance, attaches to display :0)
  5) All of the above
```

### Configuration

Edit the variables at the top of `pwnbox-init.sh` before running:

```bash
KALI_PASSWORD="kali"          # SSH login password (used by Guacamole SSH connection)
VNC_PASSWORD="kali1234"       # VNC password — max 8 characters
VNC_RESOLUTION="1920x1080"
GUAC_USERNAME="kali"
GUAC_PASSWORD="kali"          # Guacamole web login
GUAC_PORT="8080"
NX_PORT="4000"
NX_VERSION="9.4.14_1"         # Latest NoMachine stable version
```

---

## Connecting Remotely

Replace `<tailscale-ip>` with your VM's Tailscale IP (find it by running `tailscale ip -4`).

### SSH

```bash
ssh kali@<tailscale-ip>
```

Or with a tunnel to access VNC locally:

```bash
ssh -L 5901:localhost:5901 kali@<tailscale-ip>
# Then connect your VNC client to localhost:5901
```

### VNC Client

Connect directly using any VNC client:

```
Host:     <tailscale-ip>:5901
Password: kali1234
```

Recommended clients: **TigerVNC Viewer**, **RealVNC Viewer**, **Remmina** (Linux).

### Browser (Guacamole)

Open in any browser — no client install required:

```
http://<tailscale-ip>:8080/guacamole
Username: kali
Password: kali
```

Provides access to both the Kali desktop (via VNC) and a terminal (via SSH) from the same browser tab.

### NoMachine

Download the [NoMachine client](https://www.nomachine.com/download) on your remote machine, then connect to:

```
Host:     <tailscale-ip>
Port:     4000
Protocol: NX
Login:    your Kali OS username / password
```

NoMachine attaches to the existing display `:0` — you share the live session rather than creating a new one.

---

## Useful Aliases

The setup script automatically adds aliases to `~/.bashrc` and `~/.zshrc`:

```bash
# VNC
vncstart       # Start VNC server :1
vncstop        # Stop VNC server :1
vncstatus      # Show systemd service status

# Guacamole
guac-start     # Start Guacamole containers
guac-stop      # Stop Guacamole containers
guac-log       # Follow Guacamole logs
pwnbox-status  # Check VNC + SSH + Docker status

# NoMachine
nx-status      # Show NoMachine server status
nx-restart     # Restart NoMachine server
nx-log         # Follow NoMachine logs
```

---

## Cleanup

To remove any installed component:

```bash
sudo ./pwnbox-cleanup.sh
```

The cleanup script detects what's installed and lets you selectively remove components. Guacamole dependency on VNC is handled automatically — you'll be prompted if removing one would break the other.

---

## Notes

- **VMware Network Adapter**: Set to **NAT** or **Bridged** — the VM needs outbound internet access for Tailscale.
- **VNC password** is capped at 8 characters by the VNC protocol — longer passwords are silently truncated.
- **Guacamole** runs via Docker Compose. The `guacamole-home/user-mapping.xml` file stores connection credentials in plaintext — keep the VM on a trusted network.
- **NoMachine** attaches to display `:0`, meaning whoever is sitting at the physical machine sees the same session. Useful for sharing; use VNC instead if you want an isolated session.
- **Tailscale** is the recommended transport for all methods — it handles NAT traversal without exposing any ports to the public internet.

---

## License

MIT