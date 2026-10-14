# Pwnbox Control Center

Web app tự host trên ThinkPad Debian, bổ sung cho CLI hiện có. Responsive cho
iPhone/laptop, không cần aliases để bật/chọn Windows hoặc Kali và tắt desktop.
BootNext có lựa chọn Windows/Kali, mặc định trên giao diện là Windows. Chọn OS rồi
bấm **Reboot** để đặt BootNext và khởi động lại trực tiếp vào OS đó, kể cả Kali → Kali.
**Set BootNext** chỉ đặt OS cho lần boot kế tiếp, không restart/shutdown. Dropdown
là lựa chọn cho thao tác sắp gửi, không phải giá trị BootNext đọc từ firmware;
reload trang sẽ chọn Windows lại. BootNext chỉ dùng một lần; BootOrder vẫn giữ nguyên.
Hai thao tác mới chỉ dùng khi Windows/Kali đang được xác minh qua SSH.
Terminal, VNC trong web, HTB VPN, file manager và quản lý tiến trình chưa nằm trong bản này.

## Phạm vi và vận hành

- Trạng thái OS do controller xác minh qua SSH. `UNKNOWN` không đồng nghĩa OFF.
  OFF là suy luận sau shutdown có acknowledgment, LAN khỏe và desktop không phản hồi;
  không có cảm biến nguồn. Chứng cứ OFF có thời hạn theo config controller.
- Thao tác chạy trên server, được ghi vào SQLite; đóng/reload Safari vẫn xem tiếp.
  Không phát lại thao tác khi service reboot. Job đang chạy lúc service dừng trở thành
  `interrupted`: kiểm tra trạng thái trước khi thử lại. Nút xác nhận lưu công việc
  không phát hiện ứng dụng chưa lưu trên desktop.
- CPU/RAM ThinkPad và desktop, GPU/VRAM desktop: mục tiêu 5 giây khi trang foreground.
  Dữ liệu sức khỏe ThinkPad gồm nhiệt độ/pin/sạc: 15 giây; dung lượng disk: 60 giây.
  Desktop disk là phân vùng hệ thống (`C:` hoặc `/`), không phải tốc độ I/O.
- Một collector dùng chung cho các tab. Dừng lấy metrics tối đa khoảng 12 giây
  sau poll foreground cuối. Kết nối SSH chậm không tạo collector chồng nhau.
  OS detection riêng mỗi 30 giây; trong thao tác, CLI chịu trách nhiệm xác minh.
- CPU/RAM lấy qua counters OS. AMDGPU sysfs cho GPU và VRAM Kali nếu driver hỗ trợ.
  Windows dùng counters GPU Adapter Memory/GPU Engine, chọn engine bận nhất thay vì
  cộng mọi engine. Ánh xạ LUID của counters qua registry DirectX tới GPU AMD;
  loại adapter phần mềm Microsoft Basic Render Driver. Nếu không có ánh xạ,
  chỉ dùng fallback khi cả GPU và bộ counters đều là duy nhất.
  Nhiều GPU/driver không cung cấp counters sẽ hiện thiếu dữ liệu; không đoán GPU index.
  RX 9060 XT: capacity Windows là 16 GiB đã cấu hình theo phần cứng của chủ máy;
  không dùng `Win32_VideoController.AdapterRAM` (uint32, không chứa được 16 GiB).
- RAM dùng tính từ memory available trên Linux. CPU mẫu đầu chưa đủ dữ liệu có thể là
  “Chưa có dữ liệu”. Desktop metrics lỗi/cũ hơn 20 giây không hiển thị như số hiện tại.
  Thông tin disk có thời điểm đo riêng và có thể cũ tối đa chu kỳ 60 giây.
- Lưu tối đa 200 thao tác, mỗi thao tác tối đa 120 event, mỗi event 500 ký tự.
  SQLite không ghi metrics mỗi 5 giây. HTTP request poll không ghi journal.

## Demo local, không kết nối máy thật

Không cần thêm package Python:

```powershell
python web/app.py --demo
```

Mở `http://127.0.0.1:8787`. Mật khẩu demo: `pwnbox-demo`.
Banner mô phỏng luôn hiển thị sau đăng nhập; các action chỉ thay đổi state giả.
Data demo nằm trong `.local/web-demo`, độc lập config/key/state controller thật.
Demo và production chỉ bind loopback. Demo không dùng làm deployment.

## Cài trên ThinkPad đang có controller

Nếu SSH bằng mật khẩu từ laptop Windows, không cần tạo SSH key mới. Gói release
có script `INSTALL-FROM-WINDOWS.ps1` bên cạnh archive/checksum: chạy trong terminal
PowerShell tương tác. Script dùng `zwng@pwnbox-relay`, giữ host-key checking, upload
gói rồi gọi `setup/deploy-web.sh`; nhập mật khẩu SSH/sudo/web tại terminal.
Script chọn HTTPS 443 khi Serve chưa có cấu hình, hoặc 8443 khi có dịch vụ khác;
nếu 8443 đã dùng hoặc Funnel có cấu hình thì dừng để giữ các route hiện có.
Khi SSH đã kết nối và code đã copy, có thể chạy `bash setup/deploy-web.sh` từ
user controller để cài với cùng cách chọn URL/port và kiểm tra backend.

1. Cập nhật/copy repository trên ThinkPad. Không copy `.local` từ máy phát triển.
2. Xác định HTTPS origin từ hostname Tailscale/MagicDNS của ThinkPad, ví dụ
   `https://thinkpad.tailxxxx.ts.net`. Tailscale Serve/HTTPS phải được cho phép trong tailnet.
   Kiểm tra `tailscale serve status` trước để giữ dịch vụ hiện có; nếu port 443 đã được
   dùng, chọn HTTPS 8443, public_url có `:8443` và Serve `--https=8443`.
3. Chạy từ **user Debian hiện dùng controller**:

```bash
sudo bash setup/setup-web.sh --public-url https://thinkpad.tailxxxx.ts.net
sudo tailscale serve --bg http://127.0.0.1:8787
systemctl status pwnbox-web --no-pager
tailscale serve status
```

Installer hỏi mật khẩu web (ít nhất 12 ký tự), lưu PBKDF2 hash với salt, không lưu
plaintext. Chạy service bằng user controller; không chạy app bằng root.
Config/key/controller hiện có được dùng lại. Không reboot, shutdown, đổi BootOrder,
firewall, SSH authentication hoặc power settings. Installer không tự sửa Tailscale Serve.
Nếu đã có web config, mật khẩu được giữ; URL khác thì installer dừng để review.

4. Trên Kali đã có endpoint forced command, cập nhật read-only metrics khi Kali đang chạy:

```bash
sudo bash setup/update-kali-metrics.sh
```

Script giữ keys/sudoers/EFI. Thêm `metrics` và `metrics-fast` vào allowlist;
cả hai chạy Python không sudo. Setup Kali mới cũng cài helper này.
Windows không cần cài thêm agent: controller gửi script PowerShell cố định qua key
automation hiện có. Bộ đọc đã kiểm tra trực tiếp trên Windows có RX 9060 XT và
adapter phần mềm; vẫn cần xác nhận đường SSH sau mỗi lần cập nhật controller.

Cập nhật dashboard đã cài (giữ mật khẩu, lịch sử và Tailscale Serve):

```bash
bash setup/update-web.sh
```

Để dùng BootNext/Reboot khi desktop đang Kali, cần nâng cấp endpoint và sudoers
trên Kali một lần, từ repository mới (thay `0002` bằng EFI ID Kali đã xác minh):

```bash
sudo efibootmgr -v
sudo bash setup/update-kali-control.sh --kali-boot-id 0002
```

Script giữ key và Windows ID hiện có, kiểm tra cả hai entry, thêm quyền cho đúng
bốn lệnh BootNext/Reboot và lệnh `firmware` chỉ đọc. Không gửi reboot và không đặt BootNext khi cài.
Lần chạy sau có thể bỏ `--kali-boot-id` để dùng ID đã lưu. Windows dùng endpoint
hiện có, không cần thêm agent. Gói release mới vẫn dùng `UPDATE-FROM-WINDOWS.ps1`
để cập nhật ThinkPad; cập nhật endpoint Kali thực hiện riêng khi Kali đang chạy.

Bản kiểm tra BootOrder yêu cầu **cập nhật helper Kali trước, rồi cập nhật ThinkPad**.
Nếu đã nâng cấp helper trước đây, chạy lại `sudo bash setup/update-kali-control.sh`
từ gói mới để thêm lệnh `firmware` và sudoers tương ứng; ID Kali đã lưu được giữ.
Helper cũ không đọc được firmware sẽ khiến thao tác boot chưa được xác minh đầy đủ.

Các thao tác Start/Wake/BootNext/Reboot giờ kiểm tra Windows đứng đầu BootOrder khi
OS đã sẵn sàng. Trước/sau khi đặt BootNext, endpoint ghi thứ tự vào Operation details
và so sánh chính xác trên cùng OS; nếu thứ tự thay đổi thì dừng trước reboot.
Sau reboot, controller đọc thứ tự ở OS đích và kiểm tra ưu tiên Windows. Nếu không
đọc được hoặc Windows không đứng đầu, job thất bại dù OS đích có thể đã chạy.
Kiểm tra này chỉ đọc BootOrder; không tự sửa thứ tự hoặc gửi thêm reboot.
History cũ chỉ xác minh OS, không có bằng chứng BootOrder và không được diễn giải
như một lần kiểm tra ưu tiên Windows. Xem [khôi phục và chẩn đoán](boot-order-troubleshooting.md).

### Địa chỉ ngắn hoặc IP

Chạy `bash setup/update-web.sh --shortcuts` để thêm HTTP entry point trên port 80
của Tailscale. Trên Windows dùng gói release với:

```powershell
& "D:\Code\pwnbox-anywhere\.local\releases\UPDATE-FROM-WINDOWS.ps1" -Shortcuts
```

Khi kết nối Tailscale, nhập `http://pwnbox-relay` hoặc
`http://100.111.252.9:80` (installer in địa chỉ thực tế từ Tailscale status).
MagicDNS cần hoạt động để dùng tên ngắn. Listener loopback `127.0.0.1:8788`
chạy cùng tiến trình web và chỉ chuyển GET/HEAD tới HTTPS origin đã cấu hình.
Nó không phục vụ login/metrics/API, không chuyển tiếp POST và không phản chiếu
Host/path/query vào đích redirect. Đăng nhập vẫn dùng HTTPS/Secure cookie hiện có.
Nhập rõ `http://` vì tên ngắn/IP không có chứng chỉ HTTPS tương ứng.

Tailscale dùng TCP forward port 80 tới listener redirect để cả tên ngắn và IP
đều hoạt động, không phụ thuộc cách Serve HTTP chọn Host.
Script xác minh HTTPS route trước, giữ route HTTPS và từ chối ghi đè nếu port 80
đang phục vụ dịch vụ khác hoặc Funnel đang bật. Chạy lại khi đã cài đúng shortcut
là no-op. Tắt shortcut: `sudo tailscale serve --tcp=80 off`.
IP entry point vẫn chuyển sang tên HTTPS, nên không phải phương án dự phòng khi
DNS của Tailscale bị lỗi. Không đổi hostname ThinkPad hay SSH alias hiện có.

Pin hiển thị riêng nguồn AC, trạng thái sạc và ngưỡng start/end từ sysfs khi có.
Không suy đoán TLP là nguyên nhân duy nhất khi pin báo `Not charging`.

5. iPhone/laptop bật Tailscale, mở HTTPS URL ở bước 3 và đăng nhập bằng mật khẩu web.
   Có thể thêm bookmark/Add to Home Screen. Hạn chế quyền tới service này bằng
   tailnet access rules cho tài khoản/thiết bị của chủ máy.

## Xác thực và giới hạn

Giao diện Control Center dùng tiếng Anh, với sidebar desktop và bottom navigation
trên điện thoại. Hình ThinkPad/desktop và icon đều là SVG local; không tải font,
ảnh hay thư viện UI từ CDN. Thẻ metrics chỉ biểu diễn mẫu thật, không tạo biểu đồ
lịch sử giả. Màn hình xác nhận và timeline dùng action/job hiện có; không
thay đổi chu kỳ lấy metrics. BootNext/Reboot cũng dùng cùng xác nhận, lịch sử,
lock và command allowlist; reboot chỉ thành công sau khi OS cũ ngắt SSH và OS
đích được xác minh trở lại. Không tự gửi lại reboot khi mất kết nối.

Backend chỉ listen `127.0.0.1`. Tailscale Serve cung cấp HTTPS/private reachability;
ứng dụng có thêm password/session cookie HttpOnly, SameSite Strict, Secure và
CSRF token, kiểm tra Origin/Host theo public_url. Login giới hạn 5 lần sai/phút,
session hết hạn sau 7 ngày; logout thu hồi session. Server tối đa 16 request thread,
request body tối đa 4 KiB, không CORS, không arbitrary command/file API.
Không phục vụ key/config, không dùng key automation để mở interactive shell.
Quyền admin Windows của key controller vẫn là giới hạn kiến trúc hiện có.

Đổi mật khẩu/URL từ user controller và restart service (thu hồi mọi session):

```bash
python3 /usr/local/lib/pwnbox/web/app.py --set-password --public-url https://thinkpad.tailxxxx.ts.net
sudo systemctl restart pwnbox-web
```

Backend yêu cầu Host/Origin HTTPS đúng public_url; mở HTTP loopback trực tiếp ở
production sẽ bị từ chối. Dùng demo để preview local. Tailscale backend không được
expose bằng Funnel hay router port forwarding. Khi triển khai, đọc và giữ các
Serve route có sẵn; lệnh trên dành cho origin root chưa dùng.

## Kiểm thử

```bash
python3 -m unittest discover -s tests -p 'test_web.py' -v
python -m unittest discover -s tests -p 'test_windows_boot.py' -v
bash tests/test-orchestration.sh
bash tests/test-kali-control.sh
python3 tests/test-wol.py
bash tests/test-vnc-reconnect.sh
bash tests/test-metrics-endpoints.sh
```

Web tests dùng backend giả: authentication/CSRF, command allowlist, job idempotency,
lock/concurrency, history retention, restart không phát lại và đọc metrics fixture.
Không broadcast WoL hay điều khiển thiết bị thật.
Trên Windows, `./tests/test-windows-metrics.ps1` mock mọi truy vấn CIM để kiểm tra
CPU/RAM/disk và cách gộp GPU engines, không đọc hoặc sửa phần cứng thật.
`test_windows_boot.py` chạy PowerShell do controller sinh, mock cả bcdedit và shutdown:
kiểm tra BootOrder đổi, enum/set thất bại, BootNext riêng và việc dừng trước reboot.
Các test này không xác minh hành vi firmware máy thật qua một vòng boot.

Trên hardware: xác minh từng metrics khi Windows/Kali chạy, idle CPU/RAM của service,
SSH latency và driver GPU. Đo điện thực tế bằng power meter nếu cần; chưa có benchmark watt.
Theo dõi `systemctl show pwnbox-web -p MemoryCurrent -p CPUUsageNSec`, `journalctl -u pwnbox-web`.
MemoryMax=256M là giới hạn bảo vệ, không phải số RAM đã đo. Timeout action 20 phút
không tự replay; nếu tùy chỉnh CLI deadlines dài hơn thì chỉnh tương ứng trong backend.

Nguồn: [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve),
[AMDGPU sysfs](https://docs.kernel.org/gpu/amdgpu/driver-misc.html),
[GPU utilization Windows](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/).
