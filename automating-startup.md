# Guide: Automating Kali Linux VM Startup on Windows Boot

This guide covers the complete workflow to automatically log into Windows, launch VMware Workstation with the GUI, and start the Kali Linux virtual machine upon system boot.

### Step 1: Configure Windows Auto-Logon
To bypass the Windows lock screen securely without storing your password in plaintext:
1. Download the **Autologon** tool from Microsoft Sysinternals. (https://learn.microsoft.com/en-us/sysinternals/downloads/autologon)
2. Run the executable (`Autologon64.exe`) as Administrator.
3. Enter your account password and click **Enable**. The tool will configure the registry and encrypt your credentials.

---

### Step 2: Create the VM Startup Script and Scheduled Task

**1. The PowerShell Script**
Create a PowerShell script (e.g., at `D:\Scripts\start-kali.ps1`) to handle the startup sequence. This script waits for Windows services to load, opens the VMware GUI, and then powers on the VM.

```powershell
$vmx    = "D:\Vms\HTB-Kali\kali-linux-2026.1-vmware-amd64.vmx"
$vmrun  = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
$vmware = "C:\Program Files (x86)\VMware\VMware Workstation\vmware.exe"

# Wait for essential Windows services to start
Start-Sleep -Seconds 15

# Launch the VMware Workstation GUI
Start-Process $vmware

# Wait for the VMware application to initialize
Start-Sleep -Seconds 10

# Start the Kali VM (it will appear within the open VMware window)
& $vmrun start $vmx gui
```

**2. The Scheduled Task**
Open **PowerShell as Administrator** and run the following commands to create a Scheduled Task. 
*Note: Using `-AtLogon` ensures the task runs after the desktop environment is loaded, allowing the VMware GUI to render properly. The `-ExecutionPolicy Bypass` flag prevents Windows from blocking the script execution.*

```powershell
# Bypass ExecutionPolicy to prevent Windows from blocking the script
$action  = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File D:\Scripts\start-kali.ps1"

# Trigger the task immediately after the user logs in
$trigger = New-ScheduledTaskTrigger -AtLogon

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -RestartCount 2 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
    -TaskName   "Start Kali VM" `
    -Action     $action `
    -Trigger    $trigger `
    -RunLevel   Highest `
    -User       $env:USERNAME `
    -Settings   $settings `
    -Force
```

---

### Step 3: Configure Auto-Login Inside Kali Linux
To bypass the Kali login screen once the VM boots up, configure `lightdm`:

1. Open the terminal in Kali and edit the `lightdm.conf` file:
   ```bash
   sudo nano /etc/lightdm/lightdm.conf
   ```

2. Locate the `[Seat:*]` section (or add it if missing) and append the following lines:
   ```ini
   [Seat:*]
   autologin-user=kali
   autologin-user-timeout=0
   ```
3. Save the file and exit (`Ctrl+O`, `Enter`, `Ctrl+X`).