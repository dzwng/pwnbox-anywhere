# Read-only. No firmware, service, driver, or power changes.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { exit 3 }
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'"
$result = @{
    os = 'WINDOWS'; sampled_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    cpu_percent = [double]$cpu.PercentProcessorTime
    ram_total = [double]$os.TotalVisibleMemorySize * 1024
    ram_used = ([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) * 1024
    uptime = ((Get-Date) - $os.LastBootUpTime).TotalSeconds
    gpu_percent = $null; vram_used = $null; vram_total = $null; gpu_note = $null
}
# Disk is requested only once a minute by the controller.
if ($PwnboxReadDisk) {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($os.SystemDrive)'"
    $result.disk_total = [double]$disk.Size
    $result.disk_used = [double]$disk.Size - [double]$disk.FreeSpace
    $result.disk_mount = $os.SystemDrive
    $result.disk_sampled_at = $result.sampled_at
}
try {
    $cards = @(Get-CimInstance Win32_VideoController)
    $amd = @($cards | Where-Object PNPDeviceID -Match 'VEN_1002')
    $memory = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory)
    $target = @()
    if ($amd.Count -eq 1) {
        # Match the live counter LUID to the DirectX adapter identity, excluding WARP.
        $ids = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\DirectX' -ErrorAction SilentlyContinue |
            Get-ItemProperty | Where-Object { $_.VendorId -eq 0x1002 -and $_.Description -eq $amd[0].Name -and $null -ne $_.AdapterLuid } |
            ForEach-Object { $id = [uint64]$_.AdapterLuid; 'luid_0x{0:x8}_0x{1:x8}_phys_0' -f ($id -shr 32), ($id -band 0xffffffffL) })
        $target = @($memory | Where-Object { $_.Name -in $ids })
        if ($target.Count -eq 0 -and $cards.Count -eq 1 -and $memory.Count -eq 1) { $target = $memory }
    }
    if ($target.Count -eq 1) {
        $instance = $target[0].Name
        $engines = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine |
            Where-Object { $_.Name.StartsWith("pid_") -and $_.Name.Contains($instance) })
        # GPU utilization = busiest engine; sum processes on each engine, not all engines.
        $loads = @($engines | Group-Object { ($_.Name -split '_eng_', 2)[1] } |
            ForEach-Object { ($_.Group | Measure-Object UtilizationPercentage -Sum).Sum })
        if ($loads.Count -gt 0) { $result.gpu_percent = [Math]::Min(100, ($loads | Measure-Object -Maximum).Maximum) }
        $result.vram_used = [double]$target[0].DedicatedUsage
        # Win32_VideoController.AdapterRAM is a uint32 and cannot report 16 GB.
        # Configured hardware capacity; only reported after identifying the target model.
        if ($amd[0].Name -match 'RX\s*9060\s*XT') { $result.vram_total = 16GB }
    } else { $result.gpu_note = 'Cannot map counters to a single AMD GPU.' }
} catch { $result.gpu_note = 'GPU/VRAM counters are unavailable in this SSH session.' }
$result | ConvertTo-Json -Compress
