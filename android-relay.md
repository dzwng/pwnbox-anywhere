# Android/Termux relay (phương án cũ)

Setup mặc định hiện dùng [Debian relay](./debian-relay.md). Script `setup-android-termux.sh` vẫn được giữ cho Android dự phòng.

## Cài relay

Cài Tailscale, đăng nhập cùng tailnet, bật Always-on VPN nếu có và tắt battery optimization. Cài **Termux** và **Termux:Boot** từ cùng một nguồn F-Droid hoặc GitHub; mở mỗi app một lần và bật auto-start.

```bash
pkg update && pkg install -y git
git clone https://github.com/dzwng/pwnbox-anywhere.git
cd pwnbox-anywhere
bash setup-android-termux.sh
```

Script cài `openssh` + `wol`, tạo `~/.termux/boot/10-pwnbox-relay`, giữ wake lock và chạy `sshd` port `8022`. Chưa có SSH key thì hỏi password tạm. Re-run bằng `git pull` rồi `bash setup-android-termux.sh`; đã có key thì không hỏi password và không kill sshd. Dùng `--set-password` để đổi password, `--restart-sshd` để restart (rớt phiên SSH).

## SSH từ Mac

Lấy user bằng `whoami` trong Termux và IP từ Tailscale app:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_android -C 'mac-to-android'
ssh-copy-id -i ~/.ssh/pwnbox_android.pub -p 8022 <TERMUX_USER>@<ANDROID_TS_IP>
```

```sshconfig
Host pwnbox-android
    HostName <ANDROID_TS_IP>
    User <TERMUX_USER>
    Port 8022
    IdentityFile ~/.ssh/pwnbox_android
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Reboot Android rồi test `ssh pwnbox-android whoami`. Nếu vẫn muốn dùng Android, thay riêng `pc_up` trong bản alias trên Mac bằng:

```bash
pc_up() {
  ssh pwnbox-android "wol ${PWNBOX_PC_MAC}"
}
```

Sau khi key hoạt động, có thể tắt password auth trong `$PREFIX/etc/ssh/sshd_config`; validate bằng `sshd -t` trước khi restart. Giữ phương án truy cập local Termux khi restart SSH.

Cách gỡ relay cũ nằm ở [README: Uninstall Android](./README.md#android-relay-cũ). Khi chuyển sang Debian, test WoL/full flow mới trước khi gỡ Android.
