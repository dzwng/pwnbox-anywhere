# Guide: Remote Control from macOS via Tailscale

This guide covers the complete workflow to remotely wake, control, and shut down the Windows 11 host and Kali Linux VM from a MacBook over Tailscale — no port forwarding required.

---

## Overview

| Command | Action |
|---|---|
| `pc_up` | Wake Windows 11 host via WoL (sent from Android phone relay) |
| `pc_down` | Shutdown Windows 11 host |
| `kali_up` | Start Kali VM with VMware GUI in interactive session |
| `kali_down` | Gracefully stop Kali VM and close VMware |

---

## Prerequisites

- Tailscale installed and authenticated on the Kali VM, Windows host, MacBook, and Android phone
- SSH keys configured for both the Android relay (`oppo_key`) and Windows host (`windows_key`)
- WoL enabled in BIOS/UEFI and on the Windows 11 network adapter
- An Android phone on the same local network as the Windows PC (acts as WoL relay since the PC is off and cannot receive SSH directly)

---

## Step 1: Create the `Wake Kali VM` Scheduled Task on Windows

`vmrun start ... gui` spawned over SSH runs in a **non-interactive session** — VMware launches but has no desktop to render on, so the window never appears. The fix is a Scheduled Task set to run as an **Interactive** user, which attaches to the logged-in desktop session.

Open **PowerShell as Administrator** on Windows and run:

```powershell
$action = New-ScheduledTaskAction `
    -Execute "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe" `
    -Argument 'start "D:\Vms\HTB-Kali\kali-linux-2026.1-vmware-amd64.vmx" gui'

$principal = New-ScheduledTaskPrincipal `
    -UserId "hband" `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask -TaskName "Wake Kali VM" -Action $action -Principal $principal
```

> **Why `-LogonType Interactive`?** This forces the task to run within the existing desktop session of the logged-in user, allowing VMware's GUI window to render correctly.

To verify the task was created:

```powershell
Get-ScheduledTask -TaskName "Wake Kali VM"
```

---

## Step 2: Disable the Auto-Start Task (if previously configured)

If you followed the [Automating Startup guide](./automating-startup.md) and created a `Start Kali VM` task, disable it — otherwise Kali auto-starts on every boot including unintended Windows Update restarts.

```powershell
# Disable (recommended — easy to re-enable later)
Disable-ScheduledTask -TaskName "Start Kali VM"

# Or remove permanently
Unregister-ScheduledTask -TaskName "Start Kali VM" -Confirm:$false
```

To re-enable if needed:

```powershell
Enable-ScheduledTask -TaskName "Start Kali VM"
```

---

## Step 3: Add Aliases to `~/.zshrc` on macOS

```zsh
# ── Pwnbox Remote Control ──────────────────────────────────────────

# Wake Windows 11 host via WoL relay (Android phone on local network)
alias pc_up='ssh -i ~/.ssh/oppo_key -p 8022 u0_a350@100.92.138.25 "wol 10:FF:E0:C5:B2:B6"'

# Shutdown Windows 11 host
alias pc_down='ssh -i ~/.ssh/windows_key hband@100.83.173.85 "shutdown /s /t 0"'

# Start Kali VM via Scheduled Task (renders VMware GUI in interactive session)
kali_up() {
  ssh -i ~/.ssh/windows_key hband@100.83.173.85 \
    'schtasks /run /tn "Wake Kali VM"'
}

# Gracefully stop Kali VM and close VMware GUI
kali_down() {
  ssh -i ~/.ssh/windows_key hband@100.83.173.85 \
    'powershell -Command "& \"C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe\" stop \"D:\Vms\HTB-Kali\kali-linux-2026.1-vmware-amd64.vmx\" soft; Stop-Process -Name vmware -Force -ErrorAction SilentlyContinue"'
}
```

Apply changes:

```bash
source ~/.zshrc
```

---

## Typical Workflow

```
# Morning — start everything
pc_up          # Wake Windows host (~30s to boot)
kali_up        # Start Kali VM via Scheduled Task

# Evening — shut everything down
kali_down      # Stop VM + close VMware
pc_down        # Shutdown Windows host
```

If Kali needs a restart mid-session without rebooting Windows:

```bash
kali_down && kali_up
```

---

## Notes

- **`kali_up` uses a Scheduled Task** instead of direct `vmrun ... gui` over SSH because SSH sessions are non-interactive — VMware would launch invisibly without a desktop to attach to.
- **`kali_down` closes VMware entirely** (via `Stop-Process -Name vmware`) so that `kali_up` can reopen it cleanly with `gui` mode. If VMware is left open, a subsequent `vmrun start ... gui` conflicts with the existing instance.
- **`-ErrorAction SilentlyContinue`** in `kali_down` suppresses errors if VMware is already closed — safe to run even if the GUI isn't open.
- **Scheduled Tasks survive reboots** — they are stored in the Windows registry and persist until manually deleted.
- The WoL packet is relayed through an Android phone (via Termux + SSH) because the Windows PC is powered off and unreachable over Tailscale until it boots.