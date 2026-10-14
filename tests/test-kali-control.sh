#!/usr/bin/env bash
# Execute the endpoint against isolated files and command stubs; no sudo/EFI access.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export MOCK_DIR=$work
mkdir "$work/fake" "$work/pwnbox"
printf 'ID=kali\n' > "$work/os-release"
printf '0000\n' > "$work/pwnbox/windows-boot-id"
printf '0002\n' > "$work/pwnbox/kali-boot-id"
printf '0000,0002' > "$work/order"
sed -e 's|export PATH=.*|export PATH="$MOCK_DIR/fake:$PATH"|' \
    -e 's|source /etc/os-release|source "$MOCK_DIR/os-release"|' \
    -e 's|/etc/pwnbox/|$MOCK_DIR/pwnbox/|g' \
    -e 's|$EUID|${MOCK_EUID:-0}|g' "$root/setup/pwnbox-kali-control" > "$work/control"
cat > "$work/fake/efibootmgr" <<'EOF'
#!/usr/bin/env bash
set -eu
if [[ $# == 0 ]]; then
    printf 'Boot0000* Windows\nBoot0002* Kali\n'
    printf 'BootOrder: %s\n' "$(cat "$MOCK_DIR/order")"
    [[ ! -f $MOCK_DIR/next ]] || printf 'BootNext: %s\n' "$(cat "$MOCK_DIR/next")"
else
    [[ $1 == -n && $# == 2 ]] || exit 99
    printf 'bootnext:%s\n' "$2" >> "$MOCK_DIR/actions"
    [[ ${MOCK_EFI_FAIL:-0} != 1 ]] || exit 5
    [[ ${MOCK_EFI_IGNORE:-0} == 1 ]] || printf '%s' "$2" > "$MOCK_DIR/next"
    [[ ${MOCK_ORDER_CHANGE:-0} != 1 ]] || printf '0002,0000' > "$MOCK_DIR/order"
fi
EOF
cat > "$work/fake/systemd-run" <<'EOF'
#!/usr/bin/env bash
[[ $* == *'--on-active=3s /usr/bin/systemctl reboot' ]] || exit 99
printf 'reboot\n' >> "$MOCK_DIR/actions"
EOF
cat > "$work/fake/sudo" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -n && $2 == /usr/local/libexec/pwnbox-kali-control && $# == 3 ]] || exit 99
printf 'sudo:%s\n' "$3" >> "$MOCK_DIR/actions"
printf 'PWNBOX_ACCEPTED\n'
EOF
chmod +x "$work/fake/"*
count=0
run() {
    local expected=$1 rc=0; shift
    : > "$work/actions"
    bash "$work/control" "$@" > "$work/out" 2> "$work/err" || rc=$?
    [[ $rc == "$expected" ]] || { cat "$work/err"; echo "Unexpected exit $rc for $*"; exit 1; }
    count=$((count + 1))
}
actions() { [[ $(cat "$work/actions") == "$1" ]] || { cat "$work/actions"; exit 1; }; }
run 0 bootnext-kali; actions 'bootnext:0002'; [[ $(cat "$work/out") == *PWNBOX_ACCEPTED* ]]
run 0 bootnext-windows; actions 'bootnext:0000'
run 0 reboot-kali; actions $'bootnext:0002\nreboot'
run 0 reboot-windows; actions $'bootnext:0000\nreboot'
run 0 windows; actions $'bootnext:0000\nreboot'
run 0 firmware; actions ''; [[ $(cat "$work/out") == *'PWNBOX_WINDOWS_FIRST=true'* ]]
export MOCK_ORDER_CHANGE=1
run 5 reboot-kali; actions 'bootnext:0002'; [[ $(cat "$work/out") != *PWNBOX_ACCEPTED* ]]
[[ $(cat "$work/out") == *'PWNBOX_BOOT_ORDER_BEFORE=0000,0002'* && $(cat "$work/out") == *'PWNBOX_BOOT_ORDER_AFTER_SET=0002,0000'* ]]
unset MOCK_ORDER_CHANGE
run 0 firmware; actions ''; [[ $(cat "$work/out") == *'PWNBOX_WINDOWS_FIRST=false'* ]]
printf '0000,0002' > "$work/order"
export MOCK_EFI_FAIL=1
run 5 reboot-kali; actions 'bootnext:0002'; [[ $(cat "$work/out") != *PWNBOX_ACCEPTED* ]]
unset MOCK_EFI_FAIL
export MOCK_EFI_IGNORE=1
printf '0000' > "$work/next"
run 5 reboot-kali; actions 'bootnext:0002'
unset MOCK_EFI_IGNORE
printf 'invalid\n' > "$work/pwnbox/kali-boot-id"
run 2 reboot-kali; actions ''
run 2 'reboot-kali; off'; actions ''
run 2 reboot-kali extra; actions ''
export MOCK_EUID=1000
for command in firmware bootnext-kali bootnext-windows reboot-kali reboot-windows; do
    export SSH_ORIGINAL_COMMAND=$command
    run 0; actions "sudo:$command"
done
export SSH_ORIGINAL_COMMAND='reboot-kali; off'
run 2; actions ''
export SSH_ORIGINAL_COMMAND=status
run 0; actions ''; [[ $(cat "$work/out") == PWNBOX_KALI ]]
echo "PASS: $count Kali endpoint checks; no actual firmware, sudo or reboot."
