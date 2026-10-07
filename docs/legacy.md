# Legacy VMware và Android

Flow cũ đầy đủ nằm ở commit `67ec9c0`. Xem trong Git bằng `git show 67ec9c0:README.md`;
muốn sử dụng thì checkout snapshot trong một thư mục riêng để không trộn command v2.

`legacy/setup-windows.ps1` và `legacy/automating-startup.md` giữ cách tạo task
`Wake Kali VM`, VMware GUI và Windows autologon. Không chạy script này cho dual boot.
`legacy/setup-android-termux.sh` giữ Android WoL dự phòng; hướng dẫn cũ ở cùng thư mục.

V2 không chạy hai mode trong một state machine. SSH/VNC/SOCKS/SCP được giữ lại,
không cần VMware. Kali VNC helper chỉ cài VMware Tools nếu yêu cầu `--vmware-tools`.

## Migration máy đã setup

- Cập nhật bản aliases đã copy trên Mac; git pull không cập nhật ~/.config tự động.
- `kali_down` giờ shutdown toàn bộ desktop, không chỉ VM. Ưu tiên `pwnbox off`.
- Kali VNC helper mới là `pwnbox-kali`; file `/usr/local/bin/pwnbox` cũ trên Kali không
  được setup mới tự xóa. Kiểm tra trước khi gỡ thủ công nếu không còn dùng.
- Giữ task VMware/autologon/Tailscale cũ cho tới khi hardware tests v2 đã pass.
- Không dùng legacy uninstall để dọn migration: nó có thể tắt WoL hoặc gỡ SSH.
- Khi ổn định, có thể gỡ riêng task VMware và autologon nếu không còn cần.
