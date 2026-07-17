#Requires -RunAsAdministrator
<#
.SYNOPSIS
Configures (or removes) the Pwnbox workflow on a Windows 11 host.

.DESCRIPTION
Install mode (default):
- Installs and enables Windows OpenSSH Server.
- Optionally installs the Mac public key for the current administrator.
- Enables Wake-on-Magic-Packet for the selected Ethernet adapter.
- Optionally disables Windows Fast Startup.
- Creates the interactive "Wake Kali VM" task used by macOS kali_up.

Uninstall mode (-Uninstall):
- Removes the "Wake Kali VM" scheduled task.
- Removes the supplied Mac public key line, keeping any other keys intact.
- Reverts Wake-on-Magic-Packet on the given adapter.
- Optionally restores Fast Startup (-RestoreFastStartup) and/or removes
  OpenSSH Server (-RemoveOpenSSH).

By default the uninstall keeps base services (OpenSSH, Tailscale, the firewall
rule) so the host stays reachable, mirroring the Kali pwnbox.sh philosophy of
only removing what was explicitly requested.

This script intentionally does not configure Windows Autologon. Use Microsoft's
Sysinternals Autologon UI so the password is not placed in shell history.

.EXAMPLE
.\setup-windows.ps1 -VmxPath "D:\Vms\Kali\kali.vmx" -EthernetAdapter "Ethernet" -MacPublicKey $key -DisableFastStartup

.EXAMPLE
.\setup-windows.ps1 -Uninstall -EthernetAdapter "Ethernet" -MacPublicKey $key
#>

[CmdletBinding(DefaultParameterSetName = "Install")]
param(
    [Parameter(ParameterSetName = "Uninstall", Mandatory)]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = "Install", Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$VmxPath,

    [Parameter(ParameterSetName = "Install", Mandatory)]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidateNotNullOrEmpty()]
    [string]$EthernetAdapter,

    [Parameter(ParameterSetName = "Install")]
    [string]$VmrunPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",

    [Parameter(ParameterSetName = "Install")]
    [string]$WindowsUser = "$env:COMPUTERNAME\$env:USERNAME",

    [string]$TaskName = "Wake Kali VM",

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Uninstall")]
    [ValidatePattern('^ssh-(ed25519|rsa|ecdsa-sha2-nistp(256|384|521))\s+')]
    [string]$MacPublicKey,

    [Parameter(ParameterSetName = "Install")]
    [switch]$DisableFastStartup,

    [Parameter(ParameterSetName = "Uninstall")]
    [switch]$RestoreFastStartup,

    [Parameter(ParameterSetName = "Uninstall")]
    [switch]$RemoveOpenSSH,

    [Parameter(ParameterSetName = "Uninstall")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$authorizedKeysPath = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Install {
    if (-not (Test-Path -LiteralPath $VmxPath -PathType Leaf)) {
        throw "VMX file not found: $VmxPath"
    }
    if (-not (Test-Path -LiteralPath $VmrunPath -PathType Leaf)) {
        throw "vmrun.exe not found: $VmrunPath. Install VMware Workstation or pass -VmrunPath."
    }

    Write-Step "Installing Windows OpenSSH Server"
    $sshCapability = Get-WindowsCapability -Online |
        Where-Object Name -Like "OpenSSH.Server*" |
        Select-Object -First 1
    if (-not $sshCapability) {
        throw "The OpenSSH Server Windows capability was not found. Run Windows Update and retry."
    }
    if ($sshCapability.State -ne "Installed") {
        Add-WindowsCapability -Online -Name $sshCapability.Name | Out-Null
    }
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    $firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        New-NetFirewallRule `
            -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22 | Out-Null
    } else {
        Enable-NetFirewallRule -Name "OpenSSH-Server-In-TCP"
    }

    if ($MacPublicKey) {
        Write-Step "Installing the Mac SSH public key for an administrator account"
        # Only create the file when missing; New-Item -Force would truncate an
        # existing administrators_authorized_keys and drop keys already present.
        if (-not (Test-Path -LiteralPath $authorizedKeysPath)) {
            New-Item -ItemType File -Path $authorizedKeysPath | Out-Null
        }
        $existingKeys = @(Get-Content -LiteralPath $authorizedKeysPath -ErrorAction SilentlyContinue)
        if ($existingKeys -notcontains $MacPublicKey.Trim()) {
            Add-Content -LiteralPath $authorizedKeysPath -Value $MacPublicKey.Trim()
        }

        # Use well-known SIDs so this also works on non-English Windows installs.
        & icacls.exe $authorizedKeysPath /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F" | Out-Null
        Restart-Service sshd
    }

    Write-Step "Configuring Wake-on-LAN on '$EthernetAdapter'"
    $adapter = Get-NetAdapter -Name $EthernetAdapter -Physical -ErrorAction Stop
    Set-NetAdapterPowerManagement `
        -Name $adapter.Name `
        -WakeOnMagicPacket Enabled `
        -WakeOnPattern Disabled `
        -NoRestart `
        -ErrorAction Stop | Out-Null

    $magicProperty = Get-NetAdapterAdvancedProperty `
        -Name $adapter.Name `
        -RegistryKeyword "*WakeOnMagicPacket" `
        -ErrorAction SilentlyContinue
    if ($magicProperty) {
        Set-NetAdapterAdvancedProperty `
            -Name $adapter.Name `
            -RegistryKeyword "*WakeOnMagicPacket" `
            -RegistryValue 1 `
            -NoRestart | Out-Null
    }

    & powercfg.exe /deviceenablewake $adapter.InterfaceDescription | Out-Null
    Restart-NetAdapter -Name $adapter.Name

    if ($DisableFastStartup) {
        Write-Step "Disabling Windows Fast Startup"
        $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
        New-ItemProperty `
            -Path $powerKey `
            -Name HiberbootEnabled `
            -PropertyType DWord `
            -Value 0 `
            -Force | Out-Null
    }

    Write-Step "Creating the interactive VMware task '$TaskName'"
    $taskArgument = 'start "{0}" gui' -f $VmxPath
    $action = New-ScheduledTaskAction -Execute $VmrunPath -Argument $taskArgument
    $principal = New-ScheduledTaskPrincipal `
        -UserId $WindowsUser `
        -LogonType Interactive `
        -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Principal $principal `
        -Settings $settings `
        -Force | Out-Null

    Write-Step "Verification"
    $tailscale = Get-Service -Name "Tailscale" -ErrorAction SilentlyContinue
    if (-not $tailscale) {
        Write-Warning "Tailscale service was not found. Install Tailscale and sign in before remote testing."
    } elseif ($tailscale.Status -ne "Running") {
        Start-Service -Name "Tailscale"
    }

    Write-Host "Windows user : $WindowsUser"
    Write-Host "Ethernet NIC : $($adapter.Name)"
    Write-Host "MAC address  : $($adapter.MacAddress)"
    Write-Host "VMX          : $VmxPath"
    Write-Host "Task         : $TaskName"
    Write-Host "sshd         : $((Get-Service sshd).Status)"
    Write-Host ""
    Write-Host "Test the task while logged in:" -ForegroundColor Green
    Write-Host "  schtasks /run /tn `"$TaskName`""
    Write-Host ""
    Write-Host "The BIOS/UEFI Wake-on-LAN option and vendor-specific NIC properties must still be verified manually."
}

function Invoke-Uninstall {
    if (-not $Force) {
        $answer = Read-Host "Remove Pwnbox Windows configuration (task '$TaskName', Wake-on-LAN, supplied key)? [y/N]"
        if ($answer -notmatch '^[Yy]') { throw "Cancelled." }
    }

    Write-Step "Removing the scheduled task '$TaskName'"
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed task '$TaskName'."
    } else {
        Write-Host "Task '$TaskName' was not found (already removed)."
    }

    Write-Step "Removing the Mac SSH public key"
    if (-not $MacPublicKey) {
        Write-Host "No -MacPublicKey supplied; leaving administrators_authorized_keys untouched."
    } elseif (-not (Test-Path -LiteralPath $authorizedKeysPath)) {
        Write-Host "administrators_authorized_keys does not exist; nothing to remove."
    } else {
        $key = $MacPublicKey.Trim()
        $remaining = @(Get-Content -LiteralPath $authorizedKeysPath |
            Where-Object { $_.Trim() -ne $key -and $_.Trim() -ne "" })
        if ($remaining.Count -eq 0) {
            Remove-Item -LiteralPath $authorizedKeysPath -Force
            Write-Host "Removed the key and deleted the now-empty administrators_authorized_keys."
        } else {
            # ASCII keeps the file BOM-free, which Windows OpenSSH requires.
            Set-Content -LiteralPath $authorizedKeysPath -Value $remaining -Encoding ascii
            Write-Host "Removed the supplied key; kept $($remaining.Count) other key(s)."
        }
    }

    if ($EthernetAdapter) {
        Write-Step "Reverting Wake-on-LAN on '$EthernetAdapter'"
        $adapter = Get-NetAdapter -Name $EthernetAdapter -Physical -ErrorAction SilentlyContinue
        if ($adapter) {
            Set-NetAdapterPowerManagement `
                -Name $adapter.Name `
                -WakeOnMagicPacket Disabled `
                -WakeOnPattern Disabled `
                -NoRestart `
                -ErrorAction SilentlyContinue | Out-Null

            $magicProperty = Get-NetAdapterAdvancedProperty `
                -Name $adapter.Name `
                -RegistryKeyword "*WakeOnMagicPacket" `
                -ErrorAction SilentlyContinue
            if ($magicProperty) {
                Set-NetAdapterAdvancedProperty `
                    -Name $adapter.Name `
                    -RegistryKeyword "*WakeOnMagicPacket" `
                    -RegistryValue 0 `
                    -NoRestart | Out-Null
            }

            & powercfg.exe /devicedisablewake $adapter.InterfaceDescription | Out-Null
            Restart-NetAdapter -Name $adapter.Name -ErrorAction SilentlyContinue
            Write-Host "Wake-on-Magic-Packet disabled on '$($adapter.Name)'."
        } else {
            Write-Warning "Adapter '$EthernetAdapter' was not found; skipped the Wake-on-LAN revert."
        }
    } else {
        Write-Host "No -EthernetAdapter supplied; leaving Wake-on-LAN settings unchanged."
    }

    if ($RestoreFastStartup) {
        Write-Step "Restoring Windows Fast Startup"
        $powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
        New-ItemProperty `
            -Path $powerKey `
            -Name HiberbootEnabled `
            -PropertyType DWord `
            -Value 1 `
            -Force | Out-Null
        Write-Host "Fast Startup re-enabled (HiberbootEnabled = 1)."
    }

    if ($RemoveOpenSSH) {
        Write-Step "Removing Windows OpenSSH Server"
        if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
            Stop-Service -Name sshd -Force -ErrorAction SilentlyContinue
            Set-Service -Name sshd -StartupType Disabled -ErrorAction SilentlyContinue
        }
        $rule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
        if ($rule) {
            Remove-NetFirewallRule -Name "OpenSSH-Server-In-TCP"
        }
        $cap = Get-WindowsCapability -Online |
            Where-Object Name -Like "OpenSSH.Server*" |
            Select-Object -First 1
        if ($cap -and $cap.State -eq "Installed") {
            Remove-WindowsCapability -Online -Name $cap.Name | Out-Null
        }
        Write-Host "OpenSSH Server stopped, disabled, and removed."
    } else {
        Write-Host "Kept OpenSSH Server, firewall rule, and sshd (pass -RemoveOpenSSH to remove them)."
    }

    Write-Step "Uninstall complete"
    Write-Host "Not touched: Sysinternals Autologon and Tailscale. Revert those manually if you want them gone."
}

if (-not (Test-IsAdministrator)) {
    throw "Open PowerShell with 'Run as administrator' and run the script again."
}

if ($PSCmdlet.ParameterSetName -eq "Uninstall") {
    Invoke-Uninstall
} else {
    Invoke-Install
}
