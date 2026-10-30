#!/usr/bin/env bash
# Optional guest profile. Never source user configuration as shell code.
load_vm_config() {
    VM_CONFIG=${PWNBOX_VM_CONFIG:-${PWNBOX_CONFIG%/*}/vmware.conf}
    VM_ENABLED=false
    [[ -e $VM_CONFIG ]] || return 0
    VM_HOST= VM_USER= VM_SSH_PORT=22 VM_TIMEOUT=240
    VM_IDENTITY_FILE=$HOME/.ssh/pwnbox_control_kali_vm
    VM_KNOWN_HOSTS_FILE=$HOME/.ssh/pwnbox_vm_known_hosts
    local line key value
    while IFS= read -r line || [[ -n $line ]]; do
        line=${line%$'\r'}
        [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
        [[ $line =~ ^([A-Z_]+)=(.*)$ ]] || fail 2 'Invalid vmware.conf; use literal KEY=value.'
        key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
        case $key in
            VM_ENABLED|VM_HOST|VM_USER|VM_SSH_PORT|VM_TIMEOUT|VM_IDENTITY_FILE|VM_KNOWN_HOSTS_FILE) printf -v "$key" '%s' "$value";;
            *) fail 2 "Unknown VMware config key: $key";;
        esac
    done < "$VM_CONFIG"
    [[ $VM_ENABLED == true || $VM_ENABLED == false ]] || fail 2 'VM_ENABLED must be true or false.'
    $VM_ENABLED || return 0
    [[ $VM_HOST =~ ^[a-zA-Z0-9][a-zA-Z0-9.:-]*$ && $VM_USER =~ ^[a-z_][a-z0-9_-]*$ ]] || fail 2 'Invalid VM_HOST/VM_USER.'
    for key in VM_SSH_PORT VM_TIMEOUT; do
        [[ ${!key} =~ ^[1-9][0-9]{0,4}$ ]] || fail 2 "Invalid $key."
    done
    (( VM_SSH_PORT <= 65535 && VM_TIMEOUT <= 900 )) || fail 2 'VM port/timeout out of range.'
    [[ $VM_HOST != "$KALI_HOST" && $VM_HOST != "$WINDOWS_HOST" ]] || fail 2 'VM must have its own address, separate from both desktop endpoints.'
    for key in VM_IDENTITY_FILE VM_KNOWN_HOSTS_FILE; do
        value=${!key}
        [[ $value != '~/'* ]] || value="$HOME/${value#\~/}"
        [[ $value == /* && -r $value ]] || fail 2 "Cannot read $key (absolute path required)."
        printf -v "$key" '%s' "$value"
    done
    [[ ! $VM_IDENTITY_FILE -ef $KALI_IDENTITY_FILE && ! $VM_IDENTITY_FILE -ef $WINDOWS_IDENTITY_FILE ]] || fail 2 'Use a separate VM automation key.'
    if cmp -s -- "$VM_IDENTITY_FILE" "$KALI_IDENTITY_FILE" || cmp -s -- "$VM_IDENTITY_FILE" "$WINDOWS_IDENTITY_FILE"; then
        fail 2 'VM automation key duplicates a desktop key; create a separate key pair.'
    fi
}
vm_ssh() {
    timeout --kill-after=2 "${PROBE_TIMEOUT}s" ssh -F /dev/null -T \
        -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
        -o "UserKnownHostsFile=$VM_KNOWN_HOSTS_FILE" -o HostKeyAlias=pwnbox-control-kali-vm \
        -o ConnectionAttempts=1 -o "ConnectTimeout=$CONNECT_TIMEOUT" \
        -o ServerAliveInterval=2 -o ServerAliveCountMax=2 \
        -i "$VM_IDENTITY_FILE" -p "$VM_SSH_PORT" -l "$VM_USER" "$VM_HOST" "$1"
}
vm_probe() {
    local output
    output=$(vm_ssh status 2>"$STATE_DIR/probe-vm.err") || return 1
    [[ ${output//$'\r'/} == PWNBOX_KALI_VM ]]
}
vm_windows() {
    windows_ps "& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path \$env:ProgramData 'pwnbox\windows-vmware-control.ps1') '$1'; if (\$LASTEXITCODE -ne 0) { exit 5 }"
}
vm_inventory() {
    local output
    # Expand ProgramData remotely, never on the controller.
    output=$(vm_windows status 2>"$STATE_DIR/vmware.err") || return 1
    VM_INVENTORY=${output//$'\r'/}
    [[ $VM_INVENTORY == PWNBOX_VM_RUNNING || $VM_INVENTORY == PWNBOX_VM_STOPPED ]]
}
vm_status() {
    VM_STATE=DISABLED
    $VM_ENABLED || return 0
    VM_STATE=UNKNOWN
    if [[ $STATE == KALI || $STATE == OFF ]]; then VM_STATE=HOST_UNAVAILABLE; return 0; fi
    [[ $STATE == WINDOWS ]] || return 0
    : > "$STATE_DIR/probe-vm.err"
    vm_inventory || return 0
    if [[ $VM_INVENTORY == PWNBOX_VM_STOPPED ]]; then
        # A live guest contradicting inventory means a wrong endpoint/profile.
        if ! vm_probe; then VM_STATE=STOPPED; fi
    elif vm_probe; then VM_STATE=RUNNING
    else VM_STATE=GUEST_UNREACHABLE
    fi
}
vm_guard_host() {
    load_vm_config
    $VM_ENABLED || return 0
    vm_status
    [[ $VM_STATE == STOPPED ]] || fail 3 "VMware guest is $VM_STATE; run pwnbox vm-stop and verify STOPPED before switching, rebooting or powering off Windows."
}
vm_start() {
    vm_status
    [[ $VM_STATE != RUNNING ]] || { log 'Kali VMware already verified.'; return 0; }
    [[ $VM_STATE == STOPPED || $VM_STATE == GUEST_UNREACHABLE ]] || fail 3 "VMware state $VM_STATE; inspect pwnbox vm-doctor before starting."
    if [[ $VM_STATE == STOPPED ]]; then
        local output rc=0
        output=$(vm_windows start 2>"$STATE_DIR/vmware.err") || rc=$?
        if (( rc != 0 )); then
            cat "$STATE_DIR/vmware.err" >&2
            fail 5 'VM start was not acknowledged; inspect state before retrying. No second start sent.'
        fi
        [[ ${output//$'\r'/} == PWNBOX_ACCEPTED ]] || fail 5 'VM task did not acknowledge start.'
        log 'VMware interactive start task accepted; waiting for guest SSH.'
    fi
    vm_wait RUNNING
}
vm_wait() {
    local target=$1 deadline=$(( $(now) + VM_TIMEOUT ))
    while (( $(now) < deadline )); do
        probe_os WINDOWS || fail 3 'Windows host disappeared; guest result unverified.'
        vm_status
        [[ $VM_STATE != "$target" ]] || { log "Kali VMware $target verified; Windows remains running."; return 0; }
        sleep "$POLL_INTERVAL"
    done
    fail 4 "Timed out waiting for VMware $target; last state $VM_STATE. Check Windows login/task and VM SSH."
}
vm_stop() {
    [[ $STATE == WINDOWS ]] || fail 3 'VM shutdown requires a verified Windows host; no host boot action sent.'
    vm_status
    [[ $VM_STATE != STOPPED ]] || { log 'Kali VMware already STOPPED.'; return 0; }
    [[ $VM_STATE == RUNNING ]] || fail 3 "Guest is $VM_STATE; refusing unverified shutdown. Use the VMware console to shut it down cleanly."
    local output rc=0
    output=$(vm_ssh off 2>"$STATE_DIR/vmware.err") || rc=$?
    if (( rc != 0 )) || [[ ${output//$'\r'/} != PWNBOX_ACCEPTED ]]; then
        fail 5 'VM shutdown not acknowledged; inspect console before retrying. No hard power-off sent.'
    fi
    log 'Guest-only clean shutdown accepted.'
    vm_wait STOPPED
}
