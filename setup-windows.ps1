<#
.SYNOPSIS
Prepare Windows LAN control for a bare-metal dual-boot desktop.
.EXAMPLE
.\setup-windows.ps1 -CheckOnly
.EXAMPLE
.\setup-windows.ps1 -PublicKeyFile .\thinkpad-windows.pub -AllowedRemoteAddress 192.0.2.0/24 -DisableFastStartup
.DESCRIPTION
Installation requires elevated Windows PowerShell. Never changes firmware,
partitions, autologon or VMware. NIC changes are opt-in and do not restart it.
#>
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [string[]]$PublicKeyFile = @(),
    [ValidatePattern('^ssh-(ed25519|rsa|ecdsa-sha2-nistp(256|384|521))\s+')]
    [string]$MacPublicKey,
    [string[]]$AllowedRemoteAddress = @('LocalSubnet'),
    [string]$EthernetAdapter,
    [switch]$EnableWakeOnLan,
    [switch]$DisableFastStartup
)
$ErrorActionPreference = 'Stop'
$sshDirectory = Join-Path $env:ProgramData 'ssh'
$authorizedKeysPath = Join-Path $sshDirectory 'administrators_authorized_keys'
$sshdConfig = Join-Path $sshDirectory 'sshd_config'
$sshdExe = Join-Path $env:WINDIR 'System32\OpenSSH\sshd.exe'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
$isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Show-Status {
    Write-Host "Windows user: $env:USERNAME"
    Get-Service sshd -ErrorAction SilentlyContinue | Format-Table Name, Status, StartType
    Get-NetAdapter -Physical | Format-Table Name, Status, MacAddress
    Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -NotLike '127.*' |
        Format-Table InterfaceAlias, IPAddress, PrefixLength
    Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue |
        Get-NetFirewallAddressFilter | Format-Table RemoteAddress
    if ((Test-Path -LiteralPath $sshdExe) -and $isAdministrator) {
        & $sshdExe -t
        if ($LASTEXITCODE -ne 0) { throw 'OpenSSH configuration validation failed.' }
    } elseif (-not $isAdministrator) {
        Write-Warning 'sshd -t needs an elevated shell to read server private host keys; syntax not verified here.'
    }
    $powerKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
    Write-Host "Fast Startup flag: $((Get-ItemProperty -LiteralPath $powerKey).HiberbootEnabled)"
    Write-Host 'Firmware (read only):'
    & bcdedit.exe /enum firmware
    if ($LASTEXITCODE -ne 0) { Write-Warning 'Firmware enumeration needs an elevated shell.' }
}
if ($CheckOnly) { Show-Status; return }

if (-not $isAdministrator) {
    throw 'Run Windows PowerShell as administrator, or use -CheckOnly for diagnostics.'
}
$keys = @()
foreach ($file in $PublicKeyFile) {
    $key = (Get-Content -LiteralPath $file -Raw).Trim()
    if ($key -notmatch '^ssh-(ed25519|rsa|ecdsa-sha2-nistp(256|384|521))\s+[A-Za-z0-9+/=]+(?:\s+[^\r\n]*)?$') {
        throw "Not a single OpenSSH public key: $file"
    }
    $keys += $key
}
if ($MacPublicKey) { $keys += $MacPublicKey.Trim() }
if ($EnableWakeOnLan -and -not $EthernetAdapter) { throw '-EnableWakeOnLan requires -EthernetAdapter.' }

$capability = Get-WindowsCapability -Online | Where-Object Name -Like 'OpenSSH.Server*' | Select-Object -First 1
if (-not $capability) { throw 'OpenSSH Server capability not found.' }
if ($capability.State -ne 'Installed') { Add-WindowsCapability -Online -Name $capability.Name | Out-Null }
Set-Service sshd -StartupType Automatic
Start-Service sshd

$ruleName = 'OpenSSH-Server-In-TCP'
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName -DisplayName 'OpenSSH Server (LAN)' -Direction Inbound `
        -Protocol TCP -LocalPort 22 -Action Allow -Profile Any -RemoteAddress $AllowedRemoteAddress | Out-Null
} else {
    Set-NetFirewallRule -Name $ruleName -Enabled True -Profile Any -RemoteAddress $AllowedRemoteAddress
}
Write-Host 'Review other existing rules allowing TCP 22; this script manages only the named OpenSSH rule.'

if ($keys.Count -gt 0) {
    $backup = "$sshdConfig.pwnbox-backup"
    if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $sshdConfig -Destination $backup }
    $lines = @(Get-Content -LiteralPath $sshdConfig)
    # Per-user Match avoids localized group names. Insert ahead of other Match blocks.
    $begin = '# BEGIN PWNBOX ADMIN KEY'
    if ($lines -notcontains $begin) {
        $index = 0
        while ($index -lt $lines.Count -and $lines[$index] -notmatch '^\s*Match\s+') { $index++ }
        $before = @(); $after = @()
        if ($index -gt 0) { $before = @($lines[0..($index - 1)]) }
        if ($index -lt $lines.Count) { $after = @($lines[$index..($lines.Count - 1)]) }
        $lines = $before + @($begin, "Match User $($env:USERNAME.ToLowerInvariant())", `
            '    AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys', `
            'Match all', '# END PWNBOX ADMIN KEY') + $after
        $original = [IO.File]::ReadAllBytes($sshdConfig)
        Set-Content -LiteralPath $sshdConfig -Value $lines -Encoding ascii
        & $sshdExe -t
        if ($LASTEXITCODE -ne 0) {
            [IO.File]::WriteAllBytes($sshdConfig, $original)
            throw 'Invalid sshd_config; original restored.'
        }
    }
    if (-not (Test-Path -LiteralPath $authorizedKeysPath)) {
        New-Item -ItemType File -Path $authorizedKeysPath | Out-Null
    }
    $existing = @(Get-Content -LiteralPath $authorizedKeysPath)
    foreach ($key in $keys) {
        $blob = ($key -split '\s+')[1]
        if (-not ($existing | Where-Object { ($_ -split '\s+') -contains $blob })) {
            Add-Content -LiteralPath $authorizedKeysPath -Value $key -Encoding ascii
            $existing += $key
        }
    }
    $acl = [Security.AccessControl.FileSecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sidText in @('S-1-5-32-544', 'S-1-5-18')) {
        $sid = [Security.Principal.SecurityIdentifier]::new($sidText)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'Allow'))
    }
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    Set-Acl -LiteralPath $authorizedKeysPath -AclObject $acl
    & $sshdExe -t
    if ($LASTEXITCODE -ne 0) { throw 'sshd_config validation failed; service not restarted.' }
    Restart-Service sshd
}
if ($DisableFastStartup) {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
        -Name HiberbootEnabled -PropertyType DWord -Value 0 -Force | Out-Null
}
if ($EnableWakeOnLan) {
    $adapter = Get-NetAdapter -Name $EthernetAdapter -Physical
    Set-NetAdapterPowerManagement -Name $adapter.Name -WakeOnMagicPacket Enabled `
        -WakeOnPattern Disabled -NoRestart | Out-Null
    $property = Get-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*WakeOnMagicPacket' -ErrorAction SilentlyContinue
    if ($property) {
        Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*WakeOnMagicPacket' -RegistryValue 1 -NoRestart
    }
    Write-Host 'WoL settings saved without restarting NIC; verify after the next local reboot.'
}
Show-Status
Write-Host 'Next: verify ThinkPad key login and elevated bcdedit /enum firmware through SSH.'
