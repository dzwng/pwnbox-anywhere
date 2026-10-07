#!/usr/bin/env bash
windows_kali() {
    log 'Setting Windows one-time firmware boot to Kali, then clean reboot...'
    remote_action WINDOWS "\$ErrorActionPreference = 'Stop'; & bcdedit.exe /set '{fwbootmgr}' bootsequence '$KALI_WINDOWS_BCD_GUID'; if (\$LASTEXITCODE -ne 0) { exit 5 }; & shutdown.exe /r /t 0; if (\$LASTEXITCODE -ne 0) { exit 5 }; Write-Output 'PWNBOX_ACCEPTED'"
}
windows_off() {
    log 'Requesting clean Windows shutdown...'
    remote_action WINDOWS "& shutdown.exe /s /t 0; if (\$LASTEXITCODE -ne 0) { exit 5 }; Write-Output 'PWNBOX_ACCEPTED'"
}
