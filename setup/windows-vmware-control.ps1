param([Parameter(Mandatory)][ValidateSet('status', 'start')][string]$Action)
$ErrorActionPreference = 'Stop'
$config = Get-Content -LiteralPath (Join-Path $env:ProgramData 'pwnbox\vmware.json') -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $config.VmxPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $config.VmrunPath -PathType Leaf)) { throw 'VMX/vmrun is missing.' }
$lines = @(& $config.VmrunPath -T ws list 2>&1)
if ($LASTEXITCODE -ne 0 -or $lines.Count -lt 1 -or
    [string]$lines[0] -notmatch '^Total running VMs: [0-9]+$') { throw 'Cannot verify VMware inventory.' }
if ([int](([string]$lines[0]).Split(':')[1].Trim()) -ne ($lines.Count - 1)) { throw 'Incomplete VMware inventory.' }
$running = @($lines | Select-Object -Skip 1 | Where-Object {
    [string]::Equals(([string]$_).Trim(), $config.VmxPath, [StringComparison]::OrdinalIgnoreCase)
}).Count -gt 0
if ($Action -eq 'status') {
    if ($running) { 'PWNBOX_VM_RUNNING' } else { 'PWNBOX_VM_STOPPED' }
    exit 0
}
if (-not $running) {
    $task = Get-ScheduledTask -TaskName 'Pwnbox Kali VMware'
    if ($task.State -eq 'Disabled') { throw 'VMware task is disabled.' }
    # A submitted task is only acceptance. ThinkPad verifies guest SSH separately.
    Start-ScheduledTask -TaskName 'Pwnbox Kali VMware'
}
'PWNBOX_ACCEPTED'
