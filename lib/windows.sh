#!/usr/bin/env bash
windows_kali() {
    windows_reboot KALI
}
windows_off() {
    log 'Requesting clean Windows shutdown...'
    remote_action WINDOWS "& shutdown.exe /s /t 0; if (\$LASTEXITCODE -ne 0) { exit 5 }; Write-Output 'PWNBOX_ACCEPTED'"
}
windows_boot_command() {
    local target=$1 guid
    if [[ $target == KALI ]]; then guid=$KALI_WINDOWS_BCD_GUID; else guid='{bootmgr}'; fi
    windows_firmware_code
    printf '%s' "\$ErrorActionPreference = 'Stop'; \$before = Get-PwnboxBootOrder; Write-Output ('PWNBOX_BOOT_ORDER_BEFORE=' + \$before); & bcdedit.exe /set '{fwbootmgr}' bootsequence '$guid'; if (\$LASTEXITCODE -ne 0) { exit 5 }; \$after = Get-PwnboxBootOrder; Write-Output ('PWNBOX_BOOT_ORDER_AFTER_SET=' + \$after); if (\$before -ne \$after) { Write-Error -ErrorAction Continue 'Firmware BootOrder changed while setting BootNext; reboot cancelled.'; exit 5 }; "
}
windows_firmware_code() {
    cat <<'PS'
function Get-PwnboxBootOrder {
    $raw = @(& bcdedit.exe /enum '{fwbootmgr}');
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read firmware BootOrder.' };
    $ids = @(); $collect = $false; $fields = 0;
    foreach ($line in $raw) {
        if ($line -match '^\s*displayorder\s+(\{(?:bootmgr|[0-9a-f-]{36})\})\s*$') {
            $fields++; $collect = $true; $ids += $Matches[1].ToLowerInvariant();
        } elseif ($collect -and $line -match '^\s+(\{(?:bootmgr|[0-9a-f-]{36})\})\s*$') {
            $ids += $Matches[1].ToLowerInvariant();
        } else { $collect = $false };
    };
    if ($fields -ne 1 -or $ids.Count -eq 0) { throw 'Cannot parse firmware BootOrder.' };
    return ($ids -join ',');
};
PS
}
windows_firmware() {
    windows_ps "\$ErrorActionPreference = 'Stop'; $(windows_firmware_code) \$order = Get-PwnboxBootOrder; Write-Output ('PWNBOX_BOOT_ORDER=' + \$order); Write-Output ('PWNBOX_WINDOWS_FIRST=' + (\$order.Split(',')[0] -eq '{bootmgr}').ToString().ToLowerInvariant())"
}
windows_bootnext() {
    log "Setting Windows BootNext to $1 without reboot..."
    remote_action WINDOWS "$(windows_boot_command "$1")Write-Output 'PWNBOX_ACCEPTED'"
}
windows_reboot() {
    log "Setting Windows BootNext to $1, then clean reboot..."
    remote_action WINDOWS "$(windows_boot_command "$1")& shutdown.exe /r /t 0; if (\$LASTEXITCODE -ne 0) { exit 5 }; Write-Output 'PWNBOX_ACCEPTED'"
}
