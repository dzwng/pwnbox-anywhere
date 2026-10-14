#!/usr/bin/env bash
# Read-only checks. Never rewrite BootOrder or retry a firmware/power command.
firmware_snapshot() {
    local os=$1 phase=$2 output rc=0 line order= windows_first=
    if [[ $os == WINDOWS ]]; then
        output=$(windows_firmware 2>"$STATE_DIR/firmware.err") || rc=$?
    else
        output=$(ssh_control KALI firmware 2>"$STATE_DIR/firmware.err") || rc=$?
    fi
    if (( rc != 0 )); then
        cat "$STATE_DIR/firmware.err" >&2
        log "Cannot read firmware ($phase, $os; exit $rc)."
        [[ $os != KALI ]] || log 'Update the Kali control helper and its firmware sudo permission.'
        return 1
    fi
    while IFS= read -r line; do
        line=${line%$'\r'}
        case "$line" in
            PWNBOX_BOOT_ORDER=*) order=${line#*=};;
            PWNBOX_WINDOWS_FIRST=*) windows_first=${line#*=};;
        esac
    done <<< "$output"
    [[ -n $order && ( $windows_first == true || $windows_first == false ) ]] || { log "Invalid firmware snapshot ($phase, $os)."; return 1; }
    FIRMWARE_WINDOWS_FIRST=$windows_first
    log "Firmware BootOrder ($phase, $os): $order; Windows first: $windows_first"
}
firmware_verify() {
    firmware_snapshot "$STATE" "$1" || fail 5 'OS reached, but firmware BootOrder could not be verified; no further power action sent.'
    [[ $FIRMWARE_WINDOWS_FIRST == true ]] || fail 5 'OS reached, but Windows is not first in firmware BootOrder. Restore Windows priority; no automatic BootOrder repair or reboot sent.'
}
