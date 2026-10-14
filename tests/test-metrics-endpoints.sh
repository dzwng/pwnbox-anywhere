#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export METRICS_FIXTURE=$work
python_exec=${PWNBOX_TEST_PYTHON:-$(command -v python3)}
mkdir "$work/fake"
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
EOF
export PWNBOX_CONFIG=$work/config PWNBOX_STATE_DIR=$work/state
cat > "$work/fake/ssh" <<EOF
#!/usr/bin/env bash
exec "$python_exec" "$root/tests/metrics-endpoint-fixture.py" "\$@"
EOF
cat > "$work/fake/python3" <<EOF
#!/usr/bin/env bash
exec "$python_exec" "\$@"
EOF
chmod +x "$work/fake/ssh" "$work/fake/python3"
export PATH="$work/fake:$PATH"
for os in WINDOWS KALI; do
    for mode in fast disk; do
        export EXPECT_OS=$os EXPECT_MODE=$mode
        bash "$root/bin/pwnbox-metrics" "$os" "$mode" > "$work/output"
        "$python_exec" -c 'import json,os,sys; assert json.load(open(sys.argv[1]))["os"] == os.environ["EXPECT_OS"]' "$work/output"
    done
done
if bash "$root/bin/pwnbox-metrics" 'KALI; reboot' disk; then echo 'Invalid command accepted'; exit 1; fi
if bash "$root/bin/pwnbox-metrics" KALI 'disk; reboot'; then echo 'Invalid mode accepted'; exit 1; fi
echo 'PASS: OS metrics allowlist, disk cadence, strict host keys and dedicated multiplex sockets.'
