#!/usr/bin/env bash
# Regression checks without a real desktop, network connection, or sudo.
set -Eeuo pipefail
[[ $EUID -ne 0 ]] || { echo 'Run this test as a normal user.' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export MOCK_VNC_DIR=$work HOME=$work/home
mkdir -p "$work/fake" "$HOME/.config/pwnbox" "$HOME/.ssh"
printf 'test-password-file\n' > "$HOME/.config/pwnbox/passwd"
printf '#!/bin/sh\n' > "$HOME/.config/pwnbox/xstartup"
chmod +x "$HOME/.config/pwnbox/xstartup"
cat > "$work/fake/vncserver" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_VNC_DIR/server-calls"
case "$1" in
  -list)
    # Current TigerVNC lists the display without a leading colon.
    printf 'X DISPLAY #\tRFB PORT #\tPROCESS ID\n1\t5901\t1234\n';;
  :1)
    [[ ${MOCK_VNC_FAIL:-0} == 0 ]] || exit 22
    if [[ -f $MOCK_VNC_DIR/server-live && " $* " != *' -useold '* ]]; then
      echo 'A Xtigervnc server is already running for display :1' >&2; exit 1
    fi
    if [[ ! -f $MOCK_VNC_DIR/server-live ]]; then
      touch "$MOCK_VNC_DIR/server-live"
      printf 'created\n' >> "$MOCK_VNC_DIR/desktop-creations"
    fi;;
  *) exit 90;;
esac
EOF
cat > "$work/fake/ssh" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_VNC_DIR/ssh-calls"
case " $* " in
  *' pwnbox-kali vnc start '*) exit "${MOCK_SSH_START_FAIL:-0}";;
  *' pwnbox-kali vnc stop '*) exit "${MOCK_SSH_STOP_FAIL:-0}";;
  *' -O check '*) [[ -f $MOCK_VNC_DIR/tunnel-live ]];;
  *' -O exit '*) rm -f "$MOCK_VNC_DIR/tunnel-live";;
  *' -fN -L 127.0.0.1:5901:127.0.0.1:5901 '*)
    [[ ${MOCK_TUNNEL_FAIL:-0} == 0 ]] || exit 24
    touch "$MOCK_VNC_DIR/tunnel-live"
    printf 'opened\n' >> "$MOCK_VNC_DIR/tunnel-creations";;
  *) exit 91;;
esac
EOF
chmod +x "$work/fake/"*
export PATH="$work/fake:$PATH"

# Starting again must reuse the desktop, including with the current list format.
bash "$root/pwnbox.sh" vnc start > "$work/output"
bash "$root/pwnbox.sh" vnc start >> "$work/output"
[[ $(wc -l < "$work/desktop-creations") -eq 1 ]]
[[ $(grep -c -- '-useold' "$work/server-calls") -eq 2 ]]
[[ $(grep -c -- '-localhost yes' "$work/server-calls") -eq 2 ]]
! grep -q -- '-kill' "$work/server-calls"
rc=0
MOCK_VNC_FAIL=1 bash "$root/pwnbox.sh" vnc start > "$work/output" 2>&1 || rc=$?
[[ $rc -eq 22 ]]

source "$root/macos-pwnbox.zsh.example"
# Repeated connect creates only one background tunnel.
pwnbox_vnc > "$work/output"
pwnbox_vnc >> "$work/output"
[[ $(wc -l < "$work/tunnel-creations") -eq 1 ]]
grep -q -- '-M -S .*pwnbox-vnc.sock.*-fN -L 127.0.0.1:5901:127.0.0.1:5901' "$work/ssh-calls"
pwnbox_vnc_disconnect >> "$work/output"
[[ ! -f $work/tunnel-live && -f $work/server-live ]]
! grep -q 'pwnbox-kali vnc stop' "$work/ssh-calls"
pwnbox_vnc >> "$work/output"
[[ $(wc -l < "$work/tunnel-creations") -eq 2 ]]
rc=0
MOCK_SSH_STOP_FAIL=23 pwnbox_vnc_stop > "$work/output" 2>&1 || rc=$?
[[ $rc -eq 23 && -f $work/tunnel-live ]]
pwnbox_vnc_stop >> "$work/output"
[[ ! -f $work/tunnel-live ]]
pwnbox_vnc_disconnect >> "$work/output" # already disconnected
rc=0
MOCK_SSH_START_FAIL=23 pwnbox_vnc > "$work/output" 2>&1 || rc=$?
[[ $rc -eq 23 && ! -f $work/tunnel-live ]]
rc=0
MOCK_TUNNEL_FAIL=1 pwnbox_vnc > "$work/output" 2>&1 || rc=$?
[[ $rc -eq 24 && ! -f $work/tunnel-live ]]
echo 'PASS: desktop reuse, background tunnel reuse/reconnect, disconnect, stop, and failure propagation.'
