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
export PWNBOX_CONFIG=$work/config
count=0
reset() {
    printf '%s' "$1" > "$work/desktop"
    printf 'WINDOWS,KALI' > "$work/boot-order"
    : > "$work/actions"
    rm -f -- "$work/state/"state-*
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
reset WINDOWS; run 0 status; [[ $(cat "$work/out") == WINDOWS ]]
reset KALI; run 0 status; [[ $(cat "$work/out") == KALI ]]
reset BOTH; run 3 status; [[ $(cat "$work/out") == UNKNOWN ]]
reset ALIVE; run 3 status; [[ $(cat "$work/out") == UNKNOWN ]]
reset OFF; run 3 status; [[ $(cat "$work/out") == UNKNOWN ]]
reset WINDOWS; run 0 windows; actions ''
reset KALI; run 0 kali; actions ''
reset WINDOWS; run 0 wake; actions ''
reset KALI; run 0 wake; actions ''
reset OFF; run 0 windows; actions wake
reset OFF; run 0 wake; actions wake
reset OFF; run 0 kali; actions $'wake\nwindows->kali'
reset WINDOWS; run 0 kali; actions 'windows->kali'
reset KALI; run 0 windows; actions 'kali->windows'
reset WINDOWS; run 0 bootnext-kali; actions 'windows->bootnext-kali'; [[ $(cat "$work/desktop") == WINDOWS ]]
reset WINDOWS; run 0 bootnext-windows; actions 'windows->bootnext-windows'; [[ $(cat "$work/desktop") == WINDOWS ]]
reset KALI; run 0 bootnext-kali; actions 'kali->bootnext-kali'; [[ $(cat "$work/desktop") == KALI ]]
reset KALI; run 0 bootnext-windows; actions 'kali->bootnext-windows'; [[ $(cat "$work/desktop") == KALI ]]
reset WINDOWS; run 0 reboot-kali; actions 'windows->kali'; [[ $(cat "$work/desktop") == KALI ]]
reset WINDOWS; run 0 reboot-windows; actions 'windows->windows'; [[ $(cat "$work/desktop") == WINDOWS ]]
reset KALI; run 0 reboot-kali; actions 'kali->reboot-kali'; [[ $(cat "$work/desktop") == KALI ]]
reset KALI; run 0 reboot-windows; actions 'kali->reboot-windows'; [[ $(cat "$work/desktop") == WINDOWS ]]
for state in OFF BOTH ALIVE; do
    reset "$state"; run 3 bootnext-kali; actions ''
    reset "$state"; run 3 reboot-kali; actions ''
done
reset WINDOWS; export MOCK_ACTION_FAIL=1; run 5 reboot-kali; actions 'windows->kali'; [[ $(cat "$work/desktop") == WINDOWS ]]
reset KALI; export MOCK_ACTION_FAIL=1; run 5 reboot-kali; actions 'kali->reboot-kali'; [[ $(cat "$work/desktop") == KALI ]]
reset WINDOWS; export MOCK_NO_REBOOT=1; run 4 reboot-windows; actions 'windows->windows'
reset KALI; export MOCK_NO_REBOOT=1; run 4 reboot-kali; actions 'kali->reboot-kali'
reset WINDOWS; export MOCK_DISCONNECT=1; run 5 bootnext-kali; actions 'windows->bootnext-kali'
reset KALI; export MOCK_NO_ACK=1; run 5 bootnext-kali; actions 'kali->bootnext-kali'
reset KALI; export MOCK_DISCONNECT=1; run 0 reboot-kali; actions 'kali->reboot-kali'
reset WINDOWS; run 2 'reboot-kali; off'; actions ''
reset WINDOWS; export MOCK_ORDER_CHANGE_ON_SET=1; run 5 reboot-kali; actions 'windows->kali'; [[ $(cat "$work/desktop") == WINDOWS ]]
[[ $(cat "$work/err") == *'Firmware BootOrder before setting BootNext:'* && $(cat "$work/err") == *'Firmware BootOrder after setting BootNext:'* ]]
reset WINDOWS; export MOCK_ORDER_CHANGE_ON_BOOT=1; run 5 kali; actions 'windows->kali'; [[ $(cat "$work/desktop") == KALI ]]
[[ $(cat "$work/err") == *'Windows is not first in firmware BootOrder'* ]]
reset KALI; export MOCK_ORDER_CHANGE_ON_BOOT=1; run 5 reboot-windows; actions 'kali->reboot-windows'; [[ $(cat "$work/desktop") == WINDOWS ]]
reset WINDOWS; export MOCK_ORDER_CHANGE_ON_BOOT=1; run 5 reboot-windows; actions 'windows->windows'
reset OFF; export MOCK_ORDER_CHANGE_ON_BOOT=1; run 5 windows; actions wake
reset WINDOWS; export MOCK_FIRMWARE_UNAVAILABLE=1; run 5 reboot-kali; actions ''
reset KALI; export MOCK_FIRMWARE_UNAVAILABLE=1; run 5 windows; actions ''
reset WINDOWS; printf 'KALI,WINDOWS' > "$work/boot-order"; run 5 windows; actions ''
reset WINDOWS; run 0 off; actions 'windows->off'; run 0 status; [[ $(cat "$work/out") == OFF ]]
run 0 off; actions 'windows->off'
reset KALI; run 0 off; actions 'kali->off'
reset OFF; run 3 off; actions ''
reset WINDOWS; export MOCK_ACTION_FAIL=1; run 5 kali; [[ $(cat "$work/desktop") == WINDOWS ]]; actions 'windows->kali'
reset WINDOWS; export MOCK_DISCONNECT=1; run 0 kali; actions 'windows->kali'
reset WINDOWS; export MOCK_DISCONNECT=1; run 3 off; actions 'windows->off'
reset OFF; export MOCK_WOL_FAIL=1
printf 'WOL_RETRY_INTERVAL=1\n' >> "$work/config"
run 4 wake; [[ $(wc -l < "$work/actions") -le 3 ]]
reset WINDOWS; export MOCK_LAN_DOWN=1; run 3 off; actions ''
reset WINDOWS; export MOCK_HUNG=1; run 3 status
reset WINDOWS
identity=$(printf '%s' '02:00:00:00:00:20|192.0.2.20|192.0.2.20' | cksum)
state_file="$work/state/state-${identity%% *}"
printf 'TRANSITIONING KALI %s\n' "$(( $(date +%s) + 60 ))" > "$state_file"
printf OFF > "$work/desktop"; run 0 status; [[ $(cat "$work/out") == TRANSITIONING ]]
printf 'TRANSITIONING KALI 1\n' > "$state_file"; run 3 status
printf 'OFF NONE 1\n' > "$state_file"; run 3 status
reset WINDOWS
cp "$work/config" "$work/config.orig"
printf 'WINDOWS_HOST=$(touch %s/injected)\n' "$work" >> "$work/config"
run 2 status; [[ ! -e $work/injected ]]
cp "$work/config.orig" "$work/config"
printf 'TYPO=1\n' >> "$work/config"; run 2 status
cp "$work/config.orig" "$work/config"
if [[ -n $native_flock ]]; then
    exec 8>"$work/state/operation.lock"
    flock -n 8
    run 6 kali; actions ''
    flock -u 8
else
    export MOCK_LOCKED=1; run 6 kali; actions ''
fi
printf 'PASS: %s command checks; no real SSH, firmware, shutdown or WoL.\n' "$count"
