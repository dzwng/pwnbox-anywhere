#!/usr/bin/env bash
# Forced-command allowlist checks with isolated OS/virtualization/sudo stubs.
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export MOCK_DIR=$work
mkdir "$work/fake"
printf 'ID=kali\n' > "$work/os-release"
sed -e 's|export PATH=.*|export PATH="$MOCK_DIR/fake:$PATH"|' \
    -e 's|source /etc/os-release|source "$MOCK_DIR/os-release"|' \
    -e 's|$EUID|${MOCK_EUID:-1000}|g' "$root/setup/pwnbox-kali-vm-control" > "$work/control"
cat > "$work/fake/systemd-detect-virt" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_VIRT:-vmware}"
EOF
cat > "$work/fake/sudo" <<'EOF'
#!/usr/bin/env bash
[[ $* == '-n /usr/local/libexec/pwnbox-kali-vm-control off' ]] || exit 99
printf 'sudo:off\n' >> "$MOCK_DIR/actions"
echo PWNBOX_ACCEPTED
EOF
cat > "$work/fake/systemd-run" <<'EOF'
#!/usr/bin/env bash
[[ $* == '--quiet --collect --unit=pwnbox-vm-poweroff --on-active=3s /usr/bin/systemctl poweroff' ]] || exit 99
printf 'guest-poweroff\n' >> "$MOCK_DIR/actions"
EOF
chmod +x "$work/fake/"*
count=0
run() {
    local expected=$1 rc=0; shift
    : > "$work/actions"
    bash "$work/control" "$@" > "$work/out" 2> "$work/err" || rc=$?
    [[ $rc == "$expected" ]] || { cat "$work/err"; echo "Expected $expected, got $rc"; exit 1; }
    count=$((count + 1))
}
export SSH_ORIGINAL_COMMAND=status
run 0; [[ $(cat "$work/out") == PWNBOX_KALI_VM && ! -s $work/actions ]]
export SSH_ORIGINAL_COMMAND=off
run 0; [[ $(cat "$work/actions") == sudo:off ]]
for command in windows reboot-kali bootnext-windows firmware metrics bash 'off; reboot' ''; do
    export SSH_ORIGINAL_COMMAND=$command
    run 2; [[ ! -s $work/actions ]]
done
export SSH_ORIGINAL_COMMAND=status
run 2 extra; [[ ! -s $work/actions ]]
export MOCK_VIRT=none
run 3; [[ ! -s $work/actions ]]
export MOCK_VIRT=vmware MOCK_EUID=0
run 0 off; [[ $(cat "$work/actions") == guest-poweroff && $(cat "$work/out") == PWNBOX_ACCEPTED ]]
run 2 windows; [[ ! -s $work/actions ]]
run 2; [[ ! -s $work/actions ]]
echo "PASS: $count VM endpoint checks; no real sudo, EFI or shutdown."
