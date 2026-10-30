# Legacy VMware và Android

Flow cũ đầy đủ nằm ở commit `67ec9c0`. Xem trong Git bằng `git show 67ec9c0:README.md`.
Để dùng VMware cùng dashboard hiện tại, theo [runbook VMware](vmware.md): không cần
checkout/chạy aliases cũ, không chạy lại legacy installer/uninstall.

`legacy/setup-windows.ps1` và `legacy/automating-startup.md` giữ cách tạo task
`Wake Kali VM`, VMware GUI và Windows autologon. Không chạy script này cho dual boot.
`legacy/setup-android-termux.sh` giữ Android WoL dự phòng; hướng dẫn cũ ở cùng thư mục.

State machine desktop vẫn chỉ nhận Windows/Kali bare metal. VMware là guest profile
riêng dùng chung khóa ghi, có trạng thái riêng; guest online không bị nhận nhầm thành
Kali bare metal. Kali VNC helper chỉ cài VMware Tools nếu yêu cầu `--vmware-tools`.

## Migration máy đã setup

- Cập nhật bản aliases đã copy trên Mac; git pull không cập nhật ~/.config tự động.
- `kali_down` giờ shutdown toàn bộ desktop, không chỉ VM. Ưu tiên `pwnbox off`.
- Kali VNC helper mới là `pwnbox-kali`; file `/usr/local/bin/pwnbox` cũ trên Kali không
  được setup mới tự xóa. Kiểm tra trước khi gỡ thủ công nếu không còn dùng.
- Giữ task VMware/autologon/Tailscale cũ cho tới khi hardware tests v2 đã pass.
- Không dùng legacy uninstall để dọn migration: nó có thể tắt WoL hoặc gỡ SSH.
- Nếu dùng VMware mới, giữ autologon/interactive login; adapter mới tạo task riêng,
  có thể backup và disable task `Wake Kali VM` sau khi test thay vì gỡ WoL/SSH.
