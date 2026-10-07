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
PROBE_TIMEOUT=1
POLL_INTERVAL=1
WAKE_TIMEOUT=4
BOOT_TIMEOUT=4
SHUTDOWN_TIMEOUT=4
WOL_RETRY_INTERVAL=30
OFF_SAMPLES=2
EOF
export PWNBOX_CONFIG=$work/config
count=0
reset() {
    printf '%s' "$1" > "$work/desktop"
    : > "$work/actions"
    rm -f -- "$work/state/"state-*
    unset MOCK_ACTION_FAIL MOCK_DISCONNECT MOCK_HUNG MOCK_WOL_FAIL MOCK_LAN_DOWN MOCK_LOCKED
}
run() {
    local expected=$1 rc=0; shift
    bash "$root/bin/pwnbox" "$@" > "$work/out" 2> "$work/err" || rc=$?
    if [[ $rc != "$expected" ]]; then
        cat "$work/out" "$work/err"
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
