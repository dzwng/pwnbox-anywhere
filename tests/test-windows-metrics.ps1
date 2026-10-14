# All CIM queries are replaced by fixtures. Does not contact or change any device.
$ErrorActionPreference = 'Stop'
$taskMultipleAdapters = $false
$taskExtraCounters = $false
$taskRegistryMapping = $false
function Get-ChildItem { param($Path, $ErrorAction); if ($taskRegistryMapping) { [pscustomobject]@{VendorId=0x1002; Description='AMD Radeon RX 9060 XT'; AdapterLuid=0x100000002L} } }
function Get-ItemProperty { process { $_ } }
function Get-CimInstance {
    param([string]$ClassName, [string]$Filter)
    switch ($ClassName) {
        Win32_OperatingSystem { [pscustomobject]@{TotalVisibleMemorySize=33554432; FreePhysicalMemory=25165824; LastBootUpTime=(Get-Date).AddHours(-2); SystemDrive='C:'} }
        Win32_PerfFormattedData_PerfOS_Processor { [pscustomobject]@{PercentProcessorTime=25} }
        Win32_LogicalDisk { [pscustomobject]@{Size=100GB; FreeSpace=60GB} }
        Win32_VideoController {
            [pscustomobject]@{Name='AMD Radeon RX 9060 XT'; PNPDeviceID='PCI\VEN_1002'}
            if ($taskMultipleAdapters) { [pscustomobject]@{Name='Intel'; PNPDeviceID='PCI\VEN_8086'} }
        }
        Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory {
            [pscustomobject]@{Name='luid_0x00000001_0x00000002_phys_0'; DedicatedUsage=2GB}
            if ($taskExtraCounters) { [pscustomobject]@{Name='luid_0x00000000_0x00000003_phys_0'; DedicatedUsage=3GB} }
        }
        Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine {
            [pscustomobject]@{Name='pid_1_luid_0x00000001_0x00000002_phys_0_eng_0_engtype_3D'; UtilizationPercentage=30}
            [pscustomobject]@{Name='pid_2_luid_0x00000001_0x00000002_phys_0_eng_0_engtype_3D'; UtilizationPercentage=20}
            [pscustomobject]@{Name='pid_3_luid_0x00000001_0x00000002_phys_0_eng_1_engtype_Copy'; UtilizationPercentage=90}
            if ($taskExtraCounters) { [pscustomobject]@{Name='pid_4_luid_0x00000000_0x00000003_phys_0_eng_0_engtype_3D'; UtilizationPercentage=100} }
        }
        default { throw "Unexpected hardware query: $ClassName" }
    }
}
$taskScript = Join-Path $PSScriptRoot '../web/windows-metrics.ps1'
$PwnboxReadDisk = $true
$taskData = (& $taskScript) | ConvertFrom-Json
if ($taskData.cpu_percent -ne 25 -or $taskData.ram_used -ne 8GB -or $taskData.disk_used -ne 40GB) { throw 'CPU/RAM/disk fixture mismatch' }
if ($taskData.gpu_percent -ne 90 -or $taskData.vram_used -ne 2GB -or $taskData.vram_total -ne 16GB) { throw 'GPU aggregation or 16 GiB capacity mismatch' }
$PwnboxReadDisk = $false
$taskData = (& $taskScript) | ConvertFrom-Json
if ($null -ne $taskData.disk_total) { throw 'Disk sampled on fast request' }
$taskMultipleAdapters = $true
$taskData = (& $taskScript) | ConvertFrom-Json
if ($null -ne $taskData.gpu_percent -or $null -ne $taskData.vram_used) { throw 'Ambiguous GPU attributed to Radeon' }
$taskExtraCounters = $true
$taskRegistryMapping = $true
$taskData = (& $taskScript) | ConvertFrom-Json
if ($taskData.gpu_percent -ne 90 -or $taskData.vram_used -ne 2GB) { throw 'LUID mapping included another adapter' }
$taskRegistryMapping = $false
$taskData = (& $taskScript) | ConvertFrom-Json
if ($null -ne $taskData.gpu_percent -or $null -ne $taskData.vram_used) { throw 'Unmapped multiple counters attributed to Radeon' }
Write-Output 'PASS: Windows metrics, busiest engine, 16 GiB VRAM, disk cadence, LUID mapping, ambiguous adapters.'
