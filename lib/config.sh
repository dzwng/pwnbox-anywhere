#!/usr/bin/env bash
load_config() {
    PWNBOX_CONFIG=${PWNBOX_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/pwnbox/pwnbox.conf}
    [[ -r $PWNBOX_CONFIG ]] || fail 2 "Missing config: $PWNBOX_CONFIG (copy config/pwnbox.conf.example)."
    WINDOWS_SSH_PORT=22 KALI_SSH_PORT=22 WINDOWS_BOOT_ID=0000 KALI_BOOT_ID=0002
    CONNECT_TIMEOUT=3 PROBE_TIMEOUT=8 POLL_INTERVAL=3 WAKE_TIMEOUT=180 BOOT_TIMEOUT=240
    SHUTDOWN_TIMEOUT=120 WOL_ATTEMPTS=3 WOL_RETRY_INTERVAL=20 OFF_SAMPLES=3 OFF_CACHE_TTL=300
    WOL_BROADCAST=255.255.255.255 WOL_PORT=9 LAN_HEALTH_HOST=
    WINDOWS_IDENTITY_FILE=$HOME/.ssh/pwnbox_control_windows
    KALI_IDENTITY_FILE=$HOME/.ssh/pwnbox_control_kali
    KNOWN_HOSTS_FILE=$HOME/.ssh/pwnbox_control_known_hosts
    local line key value number=0
    while IFS= read -r line || [[ -n $line ]]; do
        number=$((number + 1)); line=${line%$'\r'}
        [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
        [[ $line =~ ^([A-Z_]+)=(.*)$ ]] || fail 2 "Invalid config line $number; use KEY=value without shell quoting."
        key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
        case "$key" in
            DESKTOP_MAC|WINDOWS_HOST|KALI_HOST|WINDOWS_USER|KALI_USER|WINDOWS_SSH_PORT|KALI_SSH_PORT|WINDOWS_BOOT_ID|KALI_BOOT_ID|KALI_WINDOWS_BCD_GUID|WINDOWS_IDENTITY_FILE|KALI_IDENTITY_FILE|KNOWN_HOSTS_FILE|CONNECT_TIMEOUT|PROBE_TIMEOUT|POLL_INTERVAL|WAKE_TIMEOUT|BOOT_TIMEOUT|SHUTDOWN_TIMEOUT|WOL_ATTEMPTS|WOL_RETRY_INTERVAL|WOL_BROADCAST|WOL_PORT|LAN_HEALTH_HOST|OFF_SAMPLES|OFF_CACHE_TTL) printf -v "$key" '%s' "$value";;
            *) fail 2 "Unknown config key: $key";;
        esac
    done < "$PWNBOX_CONFIG"
    for key in DESKTOP_MAC WINDOWS_HOST KALI_HOST WINDOWS_USER KALI_USER KALI_WINDOWS_BCD_GUID; do
        [[ -n ${!key-} ]] || fail 2 "Missing config value: $key"
    done
    [[ $DESKTOP_MAC =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || fail 2 'Invalid DESKTOP_MAC.'
    for key in WINDOWS_HOST KALI_HOST WOL_BROADCAST LAN_HEALTH_HOST; do
        value=${!key}
        [[ -z $value || $value =~ ^[a-zA-Z0-9][a-zA-Z0-9.:-]*$ ]] || fail 2 "Invalid $key (use an IP or hostname)."
    done
    for key in WINDOWS_USER KALI_USER; do
        [[ ${!key} =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.\\@-]*$ ]] || fail 2 "Invalid $key."
    done
    for key in WINDOWS_BOOT_ID KALI_BOOT_ID; do
        [[ ${!key} =~ ^[[:xdigit:]]{4}$ ]] || fail 2 "Invalid $key."
    done
    [[ $KALI_WINDOWS_BCD_GUID =~ ^\{[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}\}$ ]] || fail 2 'Invalid Kali firmware GUID.'
    for key in WINDOWS_SSH_PORT KALI_SSH_PORT CONNECT_TIMEOUT PROBE_TIMEOUT POLL_INTERVAL WAKE_TIMEOUT BOOT_TIMEOUT SHUTDOWN_TIMEOUT WOL_ATTEMPTS WOL_RETRY_INTERVAL WOL_PORT OFF_SAMPLES OFF_CACHE_TTL; do
        value=${!key}
        [[ $value =~ ^[1-9][0-9]{0,4}$ ]] || fail 2 "Invalid positive integer: $key"
    done
    (( WINDOWS_SSH_PORT <= 65535 && KALI_SSH_PORT <= 65535 && WOL_PORT <= 65535 )) || fail 2 'Invalid port.'
    (( PROBE_TIMEOUT >= CONNECT_TIMEOUT && WOL_ATTEMPTS <= 10 )) || fail 2 'PROBE_TIMEOUT must cover CONNECT_TIMEOUT; WOL_ATTEMPTS must be <= 10.'
    for key in WINDOWS_IDENTITY_FILE KALI_IDENTITY_FILE KNOWN_HOSTS_FILE; do
        value=${!key}
        [[ $value != '~/'* ]] || value="$HOME/${value#\~/}"
        [[ $value == /* ]] || fail 2 "$key must be an absolute path or ~/path."
        printf -v "$key" '%s' "$value"
        [[ -r $value ]] || fail 2 "Cannot read $key: $value"
    done
    for key in ssh timeout python3; do command -v "$key" >/dev/null || fail 2 "Missing dependency: $key"; done
}
