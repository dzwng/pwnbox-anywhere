#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
# work is the exact directory created by mktemp; no computed deletion target.
trap 'rm -rf -- "$work"' EXIT
export MOCK_DIR=$work PWNBOX_STATE_DIR=$work/state
export PWNBOX_TEST_PYTHON=${PWNBOX_TEST_PYTHON:-$(command -v python3)}
export FIXTURE="$root/tests/fake-endpoints.py"
mkdir "$work/fake" "$work/state"
for tool in ssh python3 ping; do
    printf '#!/usr/bin/env bash\nexec "$PWNBOX_TEST_PYTHON" "$FIXTURE" %s "$@"\n' "$tool" > "$work/fake/$tool"
    chmod +x "$work/fake/$tool"
done
# Git Bash has no util-linux flock. Exercise lock rejection through a stub there;
# the same suite also runs an actual advisory-lock contention check on Linux.
native_flock=$(command -v flock || true)
probe_timeout=1
operation_timeout=4
case "$(uname -s)" in
    # Encoded audit commands are larger; native process startup/inspection can
    # exceed 3s. Use the production probe budget, not a fake 1s Linux budget.
    MINGW*|MSYS*) probe_timeout=8; operation_timeout=8;;
esac
if [[ -z $native_flock ]]; then
    printf '#!/usr/bin/env bash\n[[ ${MOCK_LOCKED:-0} != 1 ]]\n' > "$work/fake/flock"
    chmod +x "$work/fake/flock"
    echo 'Git Bash: flock shim; native contention check requires Debian.'
fi
export PATH="$work/fake:$PATH"
touch "$work/key" "$work/known_hosts"
cat > "$work/config" <<EOF
DESKTOP_MAC=02:00:00:00:00:20
WINDOWS_HOST=192.0.2.20
KALI_HOST=192.0.2.20
WINDOWS_USER=test
KALI_USER=test
KALI_WINDOWS_BCD_GUID={00000000-0000-0000-0000-000000000000}
WINDOWS_IDENTITY_FILE=$work/key
KALI_IDENTITY_FILE=$work/key
KNOWN_HOSTS_FILE=$work/known_hosts
LAN_HEALTH_HOST=192.0.2.1
CONNECT_TIMEOUT=1
PROBE_TIMEOUT=$probe_timeout
POLL_INTERVAL=1
WAKE_TIMEOUT=$operation_timeout
BOOT_TIMEOUT=$operation_timeout
SHUTDOWN_TIMEOUT=4
WOL_RETRY_INTERVAL=30
OFF_SAMPLES=2
EOF
export PWNBOX_CONFIG=$work/config PWNBOX_VM_CONFIG=$work/vmware.conf
count=0
reset() {
    printf '%s' "$1" > "$work/desktop"
    printf 'WINDOWS,KALI' > "$work/boot-order"
    : > "$work/actions"
    rm -f -- "$work/state/"state-*
    rm -f -- "$work/vmware.conf"
    printf STOPPED > "$work/vm"
    unset MOCK_VM_SSH_FAIL MOCK_VM_WRONG_MARKER MOCK_VM_INVENTORY_FAIL MOCK_VM_NO_START MOCK_VM_STAYS_ON
    unset MOCK_ACTION_FAIL MOCK_DISCONNECT MOCK_HUNG MOCK_WOL_FAIL MOCK_LAN_DOWN MOCK_LOCKED MOCK_NO_REBOOT MOCK_NO_ACK MOCK_ORDER_CHANGE_ON_SET MOCK_ORDER_CHANGE_ON_BOOT MOCK_FIRMWARE_UNAVAILABLE
}
run() {
    local expected=$1 rc=0; shift
    bash "$root/bin/pwnbox" "$@" > "$work/out" 2> "$work/err" || rc=$?
    if [[ $rc != "$expected" ]]; then
        cat "$work/out" "$work/err"
        cat "$work/state/"probe-*.err 2>/dev/null || true
        cat "$work/state/action.err" "$work/state/firmware.err" "$work/actions" 2>/dev/null || true
        [[ ! -f $work/trace ]] || tail -n 25 "$work/trace"
        echo "FAIL: $* expected exit $expected, got $rc" >&2; exit 1
    fi
    count=$((count + 1))
}
actions() { [[ $(cat "$work/actions") == "$1" ]] || { printf 'Expected: %q\nActual: %q\n' "$1" "$(cat "$work/actions")"; exit 1; }; }

profile() {
    printf 'separate-vm-key\n' > "$work/vm-key"
    touch "$work/vm-known-hosts"
    cat > "$work/vmware.conf" <<EOF
VM_ENABLED=true
VM_HOST=192.0.2.30
VM_USER=test
VM_IDENTITY_FILE=$work/vm-key
VM_KNOWN_HOSTS_FILE=$work/vm-known-hosts
VM_TIMEOUT=4
EOF
}
reset WINDOWS; run 0 vm-status; [[ $(cat "$work/out") == DISABLED ]]; actions ''
run 2 vm-start; actions ''
reset WINDOWS; profile; run 0 vm-status; [[ $(cat "$work/out") == STOPPED ]]; actions ''
run 0 vm-start; actions 'vm->start'; [[ $(cat "$work/desktop") == WINDOWS ]]
run 0 status; [[ $(cat "$work/out") == WINDOWS ]]
run 0 vm-status; [[ $(cat "$work/out") == RUNNING ]]
run 0 vm-start; actions 'vm->start'
run 3 off; run 3 kali; run 3 reboot-windows; actions 'vm->start'
run 0 bootnext-kali; actions $'vm->start\nwindows->bootnext-kali'
run 0 vm-stop; actions $'vm->start\nwindows->bootnext-kali\nvm->off'
[[ $(cat "$work/desktop") == WINDOWS && $(cat "$work/vm") == STOPPED ]]
run 0 vm-stop
run 0 kali; [[ $(cat "$work/desktop") == KALI ]]
run 0 vm-status; [[ $(cat "$work/out") == HOST_UNAVAILABLE ]]
run 3 vm-stop
reset KALI; profile; run 0 vm-start; actions $'kali->windows\nvm->start'
reset OFF; profile; run 0 vm-start; actions $'wake\nvm->start'
reset WINDOWS; profile; export MOCK_VM_NO_START=1; run 4 vm-start; actions 'vm->start'
reset WINDOWS; profile; printf RUNNING > "$work/vm"; export MOCK_VM_SSH_FAIL=1
run 3 vm-status; [[ $(cat "$work/out") == GUEST_UNREACHABLE ]]
run 3 vm-stop; run 3 off; actions ''
reset WINDOWS; profile; printf RUNNING > "$work/vm"; export MOCK_VM_WRONG_MARKER=1
run 3 vm-status; run 3 vm-stop; actions ''
reset WINDOWS; profile; export MOCK_VM_INVENTORY_FAIL=1
run 3 vm-status; [[ $(cat "$work/out") == UNKNOWN ]]
run 3 vm-start; run 3 off; actions ''
reset WINDOWS; profile; printf 'VM_HOST=192.0.2.20\n' >> "$work/vmware.conf"
run 2 vm-start; actions ''
reset WINDOWS; profile; printf 'VM_IDENTITY_FILE=%s/key\n' "$work" >> "$work/vmware.conf"
run 2 vm-start; actions ''
reset WINDOWS; profile; cp "$work/key" "$work/vm-key"
run 2 vm-start; actions ''
reset WINDOWS; profile; printf 'VM_HOST=$(touch %s/injected)\n' "$work" >> "$work/vmware.conf"
run 2 vm-start; [[ ! -e $work/injected ]]; actions ''
reset WINDOWS; profile; printf RUNNING > "$work/vm"; export MOCK_VM_STAYS_ON=1
run 4 vm-stop; actions 'vm->off'; [[ $(cat "$work/desktop") == WINDOWS ]]
reset WINDOWS; profile
if [[ -n $native_flock ]]; then
    exec 8>"$work/state/operation.lock"; flock -n 8
    run 6 vm-start; actions ''; flock -u 8
else
    export MOCK_LOCKED=1; run 6 vm-start; actions ''
fi
printf 'PASS: %s VMware command checks; guest/host separation, shared lock and no real devices.\n' "$count"
