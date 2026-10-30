#Requires -RunAsAdministrator
<# Restores only VMware integration; keeps OpenSSH, keys, WoL and autologon intact. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VmxPath,
    [string]$VmrunPath = 'C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe',
    [string]$WindowsUser = "$env:COMPUTERNAME\$env:USERNAME",
    [switch]$DisableLegacyTask
)
$ErrorActionPreference = 'Stop'
foreach ($path in @($VmxPath, $VmrunPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "File missing: $path" }
}
$VmxPath = (Resolve-Path -LiteralPath $VmxPath).Path
$VmrunPath = (Resolve-Path -LiteralPath $VmrunPath).Path
if ($VmxPath -notmatch '\.vmx$' -or $VmxPath -match '["\r\n]' -or $VmrunPath -match '["\r\n]') { throw 'Invalid VMX/vmrun path.' }
# Inventory must work in Windows before installing unattended control.
& $VmrunPath -T ws list
if ($LASTEXITCODE -ne 0) { throw 'vmrun list failed. Repair VMware and retry from the logged-in Windows desktop.' }
$target = Join-Path $env:ProgramData 'pwnbox'
New-Item -ItemType Directory -Path $target -Force | Out-Null
# Remote administrator already has broad host privileges. Protect config/helper
# from unprivileged writes; never place them in the user-writable repo directory.
& icacls.exe $target /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Cannot protect VMware control directory.' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
foreach ($name in @('vmware.json','windows-vmware-control.ps1')) {
    $existing = Join-Path $target $name
    if (Test-Path -LiteralPath $existing) { Copy-Item -LiteralPath $existing -Destination "$existing.$stamp.bak" }
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'windows-vmware-control.ps1') -Destination $target -Force
@{VmxPath=$VmxPath; VmrunPath=$VmrunPath} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $target 'vmware.json') -Encoding ascii
$old = Get-ScheduledTask -TaskName 'Pwnbox Kali VMware' -ErrorAction SilentlyContinue
if ($old) { Export-ScheduledTask -TaskName $old.TaskName | Set-Content -LiteralPath (Join-Path $target "task.$stamp.xml") -Encoding unicode }
$action = New-ScheduledTaskAction -Execute $VmrunPath -Argument ('-T ws start "{0}" gui' -f $VmxPath)
$principal = New-ScheduledTaskPrincipal -UserId $WindowsUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'Pwnbox Kali VMware' -Action $action -Principal $principal -Settings $settings -Force | Out-Null
if ($DisableLegacyTask) {
    $legacy = Get-ScheduledTask -TaskName 'Wake Kali VM' -ErrorAction SilentlyContinue
    if ($legacy) {
        Export-ScheduledTask -TaskName $legacy.TaskName | Set-Content -LiteralPath (Join-Path $target "legacy-task.$stamp.xml") -Encoding unicode
        Disable-ScheduledTask -TaskName $legacy.TaskName | Out-Null
    }
}
Write-Host "Installed task Pwnbox Kali VMware for $WindowsUser; VM was not started."
Write-Host 'Keep this user logged in (screen may be locked). Cold unattended boot needs the existing Sysinternals Autologon setup.'
Write-Host 'Test from ThinkPad: pwnbox vm-doctor. Legacy task is preserved unless -DisableLegacyTask was supplied.'
