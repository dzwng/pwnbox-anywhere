# Windows Autologon và Scheduled Task VMware (legacy, snapshot 67ec9c0)

Runbook VMware đầy đủ nằm ở snapshot `67ec9c0`. V2 xem [README](../README.md); relay xem [debian-relay.md](../debian-relay.md).

Flow được giữ lại là flow đã hoạt động ổn trước đây:

1. Mac SSH vào Debian relay `pwnbox-relay`; Debian gửi Wake-on-LAN để bật PC.
2. Sysinternals Autologon đưa Windows vào interactive desktop.
3. Mac chạy `kali_up` qua Windows SSH.
4. `kali_up` gọi Scheduled Task `Wake Kali VM`.
5. Task chạy `vmrun start "<VMX_PATH>" gui` với `LogonType Interactive`.

Không cấu hình Kali VM tự chạy ở mỗi lần Windows boot. Nhờ vậy Windows có thể boot để maintenance mà không tự tiêu thụ RAM/CPU cho VM; Kali chỉ bật khi Mac gửi `kali_up`.

Script tự động hóa nằm tại [setup-windows.ps1](./setup-windows.ps1).
