#Requires -RunAsAdministrator
<#
.SYNOPSIS
Configures a clean Windows 11 host for the Pwnbox workflow.

.DESCRIPTION
- Installs and enables Windows OpenSSH Server.
- Optionally installs the Mac public key for the current administrator.
- Enables Wake-on-Magic-Packet for the selected Ethernet adapter.
- Optionally disables Windows Fast Startup.
- Creates the interactive "Wake Kali VM" task used by macOS kali_up.

This script intentionally does not configure Windows Autologon. Use Microsoft's
Sysinternals Autologon UI so the password is not placed in shell history.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$VmxPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EthernetAdapter,

    [string]$VmrunPath = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",

    [string]$WindowsUser = "$env:COMPUTERNAME\$env:USERNAME",

    [string]$TaskName = "Wake Kali VM",

    [ValidatePattern('^ssh-(ed25519|rsa|ecdsa-sha2-nistp(256|384|521))\s+')]
    [string]$MacPublicKey,

    [switch]$DisableFastStartup
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    throw "Open PowerShell with 'Run as administrator' and run the script again."
}
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
    $authorizedKeys = Join-Path $env:ProgramData "ssh\administrators_authorized_keys"
    New-Item -ItemType File -Path $authorizedKeys -Force | Out-Null
    $existingKeys = @(Get-Content -LiteralPath $authorizedKeys -ErrorAction SilentlyContinue)
    if ($existingKeys -notcontains $MacPublicKey.Trim()) {
        Add-Content -LiteralPath $authorizedKeys -Value $MacPublicKey.Trim()
    }

    # Use well-known SIDs so this also works on non-English Windows installs.
    & icacls.exe $authorizedKeys /inheritance:r /grant "*S-1-5-32-544:F" /grant "*S-1-5-18:F" | Out-Null
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
