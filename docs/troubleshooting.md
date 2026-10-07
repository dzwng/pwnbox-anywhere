# Troubleshooting

| Hiện tượng | Kiểm tra |
|---|---|
| UNKNOWN khi PC tắt | Bình thường nếu chưa có shutdown được xác nhận; thử `pwnbox wake` |
| UNKNOWN khi OS đang chạy | `pwnbox doctor`, file `probe-*.err` trong state dir; key/user/port/host fingerprint |
| Cả hai OS được nhận diện | WINDOWS_HOST/KALI_HOST có trỏ nhầm VM hay máy khác không? |
| SSH bị timeout | LAN route, firewall, sshd; không kết luận mất điện từ timeout |
| Windows hỏi password | Kiểm tra Match User, key admin và ACL; controller dùng BatchMode nên sẽ fail |
| bcdedit Access denied | SSH account phải admin và remote session phải chạy được `bcdedit /enum firmware` |
| BootNext thất bại | Dừng; xác minh GUID/ID ở console; không tự sửa boot order/EFI |
| Shutdown không xác nhận OFF | LAN_HEALTH_HOST có trả ping không? Máy còn phản hồi? Action có ack không? |
| OFF cache hết hạn | Trả UNKNOWN để tránh dùng thông tin cũ làm bằng chứng |
| Exit 6 | Lệnh điều phối khác đang chạy; chờ timeout/completion |
| WoL không bật máy | MAC/broadcast, BIOS/ErP, Fast Startup, Ethernet, WoL sau Kali shutdown |
| TRANSITIONING quá lâu | Hết deadline sẽ UNKNOWN; kiểm tra Windows Update/console; không reboot mù |
| Mac SSH Tailscale không tới | OS/node đích có online không? Đúng MagicDNS/IP 100.x, cùng tailnet, access rules, firewall/sshd |
| Remote transfer/RDP chậm | `tailscale ping NODE` / `tailscale status`: direct hay relay/DERP; kiểm tra uplink Internet |
| VNC không khởi động | Cài helper tùy chọn; kiểm tra display :1 và service VNC cũ; không xóa global X locks |

## Exit codes

0 success; 2 cấu hình/usage/dependency; 3 UNKNOWN hoặc chưa đủ bằng chứng;
4 timeout; 5 remote action bị từ chối; 6 operation lock đang bận.

State mặc định: `~/.local/state/pwnbox`. Log action/probe chỉ chứa output lỗi,
không chứa private keys. `PWNBOX_STATE_DIR` có thể override cho diagnostics/test.
Không sửa/xóa lock khi một command còn chạy. Kill controller có thể để lại cached
transition, tự hết hạn; flock kernel tự nhả khi process kết thúc.

Chạy tests từ repo: `bash tests/test-orchestration.sh`. Fixture không kết nối máy thật.
Git Bash dùng flock shim do không có util-linux; native lock contention cần chạy lại
trên Debian. Kiểm thử giả lập không thay thế acceptance matrix trên hardware.
