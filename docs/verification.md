# Kết quả xác minh v2

Trạng thái ngày 2026-10-07 cho workstation đã được cấu hình trong phiên setup.
Các kết quả này ghi nhận máy đã thử; khi dùng trên máy khác cần chạy acceptance
matrix của [dualboot.md](dualboot.md) và xác minh host key/firmware tại console.

## Kiểm thử code

| Kiểm tra | Kết quả |
|---|---|
| Orchestration với endpoint giả | 31 checks pass trên Git Bash và Debian |
| Native flock trên Debian | Pass, từ chối operation trùng nhau |
| Magic Packet gửi tới UDP loopback | Pass, 102 byte, đúng MAC lặp 16 lần |
| VNC reconnect với endpoint giả | Pass trên Debian và Git Bash |
| Cú pháp Bash/PowerShell và git diff --check | Pass |

VNC regression kiểm tra dùng lại desktop, tunnel chạy nền, chỉ mở một tunnel,
disconnect/reconnect, stop và giữ exit code lỗi. Các test code không reboot máy
thật hay broadcast Magic Packet ra LAN.

## Máy thật và xác nhận của chủ máy

| Kiểm tra | Kết quả |
|---|---|
| Hardware acceptance chạy trên ThinkPad | SUCCESS, 13 bước, kết thúc ở Windows |
| WoL, chuyển OS hai chiều, shutdown hai OS, cold start và chọn OS idempotent | Pass trong hardware acceptance |
| Permanent BootOrder | Giữ nguyên sau vòng thử |
| Mac SSH trực tiếp tới Windows và Kali qua Tailscale | Chủ máy xác nhận đúng user ở cả hai OS |
| TigerVNC và reconnect sau cập nhật | Chủ máy xác nhận hoạt động |
| Firefox profile HTB với phép thử bật/tắt SOCKS | Chủ máy xác nhận hoạt động với website thường |
| DHCP reservation controller và desktop | Chủ máy xác nhận đã cấu hình router |
| Mac từ hotspot: controller status và Windows SSH | Chủ máy xác nhận hoạt động |
| Temporary setup SSH key | Đã thu hồi trên ThinkPad và xóa private/public ở máy setup |

Log máy thật nằm trong state directory riêng trên ThinkPad; config, key và log
cụ thể không đưa vào repository. Tailscale trực tiếp trên từng OS được dùng cho
truy cập tương tác; ThinkPad tiếp tục dùng LAN cho control.

## Để sau theo yêu cầu

VPN HTB trên Kali và truy cập website lab qua SOCKS chưa được xác minh. Phép thử
website thường chỉ xác minh browser dùng tunnel; không chứng minh route vào lab.
Windows GUI tiếp tục dùng AnyDesk hiện có của chủ máy.
