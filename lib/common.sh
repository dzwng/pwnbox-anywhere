#!/usr/bin/env bash
log() { printf '[pwnbox] %s\n' "$*" >&2; }
fail() { local code=$1; shift; log "$*"; exit "$code"; }
now() { date +%s; }
host_for() { if [[ $1 == WINDOWS ]]; then printf '%s' "$WINDOWS_HOST"; else printf '%s' "$KALI_HOST"; fi; }
init_state() {
    STATE_DIR=${PWNBOX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/pwnbox}
    umask 077
    mkdir -p -- "$STATE_DIR"
    [[ ! -L $STATE_DIR ]] || fail 2 'State directory must not be a symlink.'
    # Separate state for distinct desktop configs.
    local identity
    identity=$(printf '%s' "$DESKTOP_MAC|$WINDOWS_HOST|$KALI_HOST" | cksum)
    STATE_FILE="$STATE_DIR/state-${identity%% *}"
    IN_OPERATION=false
}
save_state() {
    local tmp
    tmp=$(mktemp "$STATE_FILE.XXXXXX")
    printf '%s %s %s\n' "$1" "$2" "$3" > "$tmp"
    mv -f -- "$tmp" "$STATE_FILE"
}
read_state() {
    CACHED_STATE=UNKNOWN CACHED_TARGET=NONE CACHED_UNTIL=0
    if [[ -f $STATE_FILE ]]; then
        read -r CACHED_STATE CACHED_TARGET CACHED_UNTIL < "$STATE_FILE" || true
        [[ $CACHED_UNTIL =~ ^[0-9]+$ ]] || CACHED_UNTIL=0
    fi
}
begin_transition() {
    IN_OPERATION=true
    save_state TRANSITIONING "$1" "$(( $(now) + $2 + 2 * PROBE_TIMEOUT ))"
}
operation_exit() {
    local code=$1
    if $IN_OPERATION && (( code != 0 )); then
        save_state UNKNOWN NONE 0
        log "Operation failed (exit $code). Inspect status before retrying."
    fi
}
ssh_control() {
    local os=$1 command=$2 host user port key
    if [[ $os == WINDOWS ]]; then
        host=$WINDOWS_HOST user=$WINDOWS_USER port=$WINDOWS_SSH_PORT key=$WINDOWS_IDENTITY_FILE
    else
        host=$KALI_HOST user=$KALI_USER port=$KALI_SSH_PORT key=$KALI_IDENTITY_FILE
    fi
    # Ignore user SSH config/multiplexers; never reuse an interactive key/session.
    timeout --kill-after=2 "${PROBE_TIMEOUT}s" ssh -F /dev/null -T \
        -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
        -o "UserKnownHostsFile=$KNOWN_HOSTS_FILE" -o "HostKeyAlias=pwnbox-control-${os,,}" \
        -o ConnectionAttempts=1 -o "ConnectTimeout=$CONNECT_TIMEOUT" \
        -o ServerAliveInterval=2 -o ServerAliveCountMax=2 \
        -i "$key" -p "$port" -l "$user" "$host" "$command"
}
windows_ps() {
    local encoded
    encoded=$(printf '%s' "\$ProgressPreference='SilentlyContinue'; $1" | python3 -c 'import base64,sys; print(base64.b64encode(sys.stdin.read().encode("utf-16le")).decode("ascii"))')
    ssh_control WINDOWS "powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded"
}
remote_action() {
    local os=$1 command=$2 output rc=0
    if [[ $os == WINDOWS ]]; then
        output=$(windows_ps "$command" 2>"$STATE_DIR/action.err") || rc=$?
    else
        output=$(ssh_control KALI "$command" 2>"$STATE_DIR/action.err") || rc=$?
    fi
    if (( rc == 255 || rc == 124 || rc == 137 )); then
        # A disconnect does not prove failure or success. Never repeat a reboot.
        log 'Control connection ended without a reliable exit status; verifying transition.'
    elif (( rc != 0 )); then
        cat "$STATE_DIR/action.err" >&2
        fail 5 "Remote $os action failed (exit $rc); no retry sent."
    elif [[ $output != *PWNBOX_ACCEPTED* ]]; then
        fail 5 'Remote endpoint did not acknowledge the action.'
    fi
    ACTION_ACK=false
    [[ $output != *PWNBOX_ACCEPTED* ]] || ACTION_ACK=true
}
