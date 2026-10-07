#!/usr/bin/env bash
# REAL hardware acceptance test. Run on the ThinkPad, with the desktop idle.
# This switches OS, shuts down and wakes the desktop; ends in Windows on success.
set -Eeuo pipefail
if [[ ( ${1:-} != --run && ${1:-} != --check ) || $# != 1 ]]; then
    echo 'Usage: bash tests/test-lan.sh --check|--run' >&2
    echo 'REAL reboot/shutdown/WoL. Save desktop work first. Run on ThinkPad.' >&2
    exit 2
fi
MODE=$1
CONTROLLER=${PWNBOX_CONTROLLER:-/usr/local/bin/pwnbox}
[[ -x $CONTROLLER ]] || { echo 'Install the controller first.' >&2; exit 2; }
LIB_ROOT=${PWNBOX_LIB_ROOT:-/usr/local/lib/pwnbox/lib}
source "$LIB_ROOT/common.sh"
source "$LIB_ROOT/config.sh"
load_config
init_state
RUN_DIR=${PWNBOX_TEST_RUN_DIR:-$STATE_DIR/hardware-$(date -u +%Y%m%dT%H%M%SZ)}
mkdir -p -- "$RUN_DIR"
exec 8>"$STATE_DIR/hardware-test.lock"
flock -n 8 || { echo 'A hardware test is already running.' >&2; exit 6; }
STEP=preflight
PASSED=0
finish() {
    local rc=$?
    if (( rc != 0 )); then
        printf 'FAILED: step=%s exit=%s\n' "$STEP" "$rc" > "$RUN_DIR/result"
        "$CONTROLLER" status > "$RUN_DIR/final-state" 2>&1 || true
        echo 'Stopped after failure; no further reboot/shutdown sent.' >&2
    fi
}
trap finish EXIT
printf 'RUNNING\n' > "$RUN_DIR/result"
printf 'Started %s; cancel between steps: touch %s/cancel\n' "$(date -u +%FT%TZ)" "$RUN_DIR"
check_cancel() {
    if [[ -e $RUN_DIR/cancel ]]; then
        STEP=cancelled
        echo 'Cancellation requested; leaving desktop in its current state.' >&2
        exit 7
    fi
}
expect_state() {
    local actual rc=0
    actual=$("$CONTROLLER" status) || rc=$?
    printf 'Expected=%s observed=%s status_exit=%s\n' "$1" "$actual" "$rc"
    [[ $rc == 0 && $actual == "$1" ]] || return 10
}
step() {
    local name=$1 command=$2 expected=$3
    check_cancel
    STEP=$name
    printf '\n%s STEP %s: pwnbox %s\n' "$(date -u +%FT%TZ)" "$STEP" "$command"
    "$CONTROLLER" "$command"
    expect_state "$expected"
    PASSED=$((PASSED + 1))
    printf 'PASSED %s %s\n' "$PASSED" "$STEP" > "$RUN_DIR/progress"
}
firmware_snapshot() {
    # Read only, run while Windows is identified. Verify the two existing entries.
    windows_ps "& bcdedit.exe /enum '{fwbootmgr}'; if (\$LASTEXITCODE -ne 0) { exit 5 }" > "$1"
    python3 - "$1" "$KALI_WINDOWS_BCD_GUID" <<'PY'
from pathlib import Path
import re, sys
text = Path(sys.argv[1]).read_text().lower()
ids = re.findall(r'\{[^}\s]+\}', text)
assert ids == ['{fwbootmgr}', '{bootmgr}', sys.argv[2].lower()], (
    'Unexpected firmware manager entries/order or a pending bootsequence: ' + repr(ids))
PY
}
expect_state WINDOWS
firmware_snapshot "$RUN_DIR/firmware-before.txt"
if [[ $MODE == --check ]]; then
    printf 'PRECHECK SUCCESS: Windows ready; firmware order expected; no action sent.\n' > "$RUN_DIR/result"
    cat "$RUN_DIR/result"
    exit 0
fi
step windows-idempotent windows WINDOWS
step wake-while-windows wake WINDOWS
step windows-to-kali kali KALI
step kali-idempotent kali KALI
step wake-while-kali wake KALI
step kali-to-windows windows WINDOWS
step windows-to-off off OFF
step off-idempotent off OFF
step off-to-windows windows WINDOWS
step windows-to-off-again off OFF
step off-to-kali kali KALI
step kali-to-off off OFF
step wake-default-windows wake WINDOWS
STEP=firmware-after
firmware_snapshot "$RUN_DIR/firmware-after.txt"
printf 'SUCCESS: %s steps; final state WINDOWS; firmware order unchanged.\n' "$PASSED" > "$RUN_DIR/result"
cat "$RUN_DIR/result"
