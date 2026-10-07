#!/usr/bin/env bash
probe_os() {
    local os=$1 output
    if [[ $os == WINDOWS ]]; then
        output=$(windows_ps "if ([Environment]::OSVersion.Platform -ne 'Win32NT') { exit 1 }; Write-Output 'PWNBOX_WINDOWS'" 2>"$STATE_DIR/probe-windows.err") || return 1
        [[ ${output//$'\r'/} == PWNBOX_WINDOWS ]]
    else
        output=$(ssh_control KALI status 2>"$STATE_DIR/probe-kali.err") || return 1
        [[ ${output//$'\r'/} == PWNBOX_KALI ]]
    fi
}
host_alive() {
    # Positive ping OR TCP response is useful; absence alone never establishes OFF.
    local host=$1 port=$2
    if command -v ping >/dev/null && timeout 2 ping -n -c 1 -W 1 "$host" >/dev/null 2>&1; then return 0; fi
    timeout --kill-after=1 3 python3 - "$host" "$port" <<'PY'
import socket, sys
try:
    with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=1):
        pass
except (OSError, ValueError):
    sys.exit(1)
PY
}
desktop_alive() { host_alive "$WINDOWS_HOST" "$WINDOWS_SSH_PORT" || host_alive "$KALI_HOST" "$KALI_SSH_PORT"; }
lan_healthy() {
    [[ -n $LAN_HEALTH_HOST ]] && command -v ping >/dev/null && timeout 2 ping -n -c 1 -W 1 "$LAN_HEALTH_HOST" >/dev/null 2>&1
}
detect_state() {
    local windows=false kali=false
    probe_os WINDOWS && windows=true
    probe_os KALI && kali=true
    if $windows && $kali; then STATE=UNKNOWN; log 'Both OS endpoints responded; check host configuration.'
    elif $windows; then STATE=WINDOWS
    elif $kali; then STATE=KALI
    else
        read_state
        STATE=UNKNOWN
        if [[ $CACHED_STATE == TRANSITIONING ]] && (( $(now) < CACHED_UNTIL )); then
            STATE=TRANSITIONING
        elif [[ $CACHED_STATE == OFF ]] && (( $(now) < CACHED_UNTIL )) && lan_healthy && ! desktop_alive; then
            STATE=OFF
        fi
    fi
}
wait_ready() {
    local target=$1 duration=$2 retry_wol=${3:-false} deadline next_wol attempts=1
    deadline=$(( $(now) + duration )); next_wol=$(( $(now) + WOL_RETRY_INTERVAL ))
    log "Waiting for $target (timeout ${duration}s)..."
    while (( $(now) < deadline )); do
        detect_state
        if [[ $STATE == WINDOWS || $STATE == KALI ]]; then
            if [[ $target == ANY || $STATE == "$target" ]]; then
                save_state "$STATE" NONE 0
                IN_OPERATION=false
                log "$STATE detected."
                return 0
            fi
        fi
        if $retry_wol && (( attempts < WOL_ATTEMPTS && $(now) >= next_wol )); then
            # Do not repeat WoL when an OS is positively identified.
            if [[ $STATE != WINDOWS && $STATE != KALI ]]; then send_wol; fi
            attempts=$((attempts + 1)); next_wol=$(( $(now) + WOL_RETRY_INTERVAL ))
        fi
        sleep "$POLL_INTERVAL"
    done
    fail 4 "Timed out waiting for $target; last observed state: $STATE."
}
wait_off() {
    local deadline samples=0
    deadline=$(( $(now) + SHUTDOWN_TIMEOUT ))
    while (( $(now) < deadline )); do
        if lan_healthy && ! desktop_alive; then samples=$((samples + 1)); else samples=0; fi
        if (( samples >= OFF_SAMPLES )); then
            $ACTION_ACK || fail 3 'Desktop stopped responding, but shutdown was not acknowledged; power state UNKNOWN.'
            save_state OFF NONE "$(( $(now) + OFF_CACHE_TTL ))"
            IN_OPERATION=false
            log 'OFF inferred: shutdown acknowledged, LAN healthy, desktop no longer responds.'
            return 0
        fi
        sleep "$POLL_INTERVAL"
    done
    fail 4 'Shutdown not verified. Check LAN_HEALTH_HOST and the desktop console.'
}
