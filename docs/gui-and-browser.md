# Kali GUI và browser lab trên Mac

Hai cách dùng bổ sung cho nhau: TigerVNC cho desktop XFCE/tool GUI; Firefox trên
Mac qua SOCKS5 cho website lab. SSH của cả hai đi trực tiếp tới Tailscale Kali.
VPN HTB chạy trên Kali; không cần quảng bá mạng lab qua Tailscale.

## TigerVNC

Trên Kali, từ shell của user tương tác (ví dụ `your_kali_user`):

```bash
sudo bash pwnbox.sh install
```

Installer cài TigerVNC, dbus-x11, SSH và XFCE nếu chưa có; hỏi mật khẩu VNC 6–8
ký tự ngay trong terminal. Nhập mật khẩu sudo/VNC tại máy, không đưa vào chat.
Helper được cài thành `/usr/local/bin/pwnbox-kali`. Desktop mặc định 1920x1080,
display `:1`, chỉ nghe localhost. Đây là phiên XFCE riêng, không chia sẻ màn hình
vật lý. Khởi động VNC theo nhu cầu; không cần autologin.

Trên Mac đã có aliases và SSH tương tác:

```bash
pwnbox_vnc
```

Tunnel SSH chạy nền và terminal trả về prompt. Mở VNC viewer và kết nối
`127.0.0.1:5901`, nhập mật khẩu VNC đã đặt. Với Screen Sharing tích hợp trên macOS:

```bash
open vnc://127.0.0.1:5901
```

Đóng viewer không dừng desktop hoặc tunnel. Ngắt tunnel bằng
`pwnbox_vnc_disconnect`; ứng dụng trong desktop VNC tiếp tục chạy. Kết nối lại bằng
`pwnbox_vnc`, helper dùng lại phiên `:1` hiện có. Khi muốn kết thúc cả desktop VNC,
lưu công việc trong phiên rồi chạy:

```bash
pwnbox_vnc_stop
```

Đổi độ phân giải trong `~/.config/pwnbox/config` trên Kali, ví dụ
`VNC_RESOLUTION=1920x1200`, rồi stop/start VNC để áp dụng. Kiểm tra server:

```bash
ssh kali 'pwnbox-kali vnc status'
ssh kali 'ss -ltn | grep :5901'
```

Cổng 5901 phải chỉ nghe loopback (`127.0.0.1`/`[::1]`). Khi lỗi startup, xem đường
dẫn log do `vncserver` in ra; tùy phiên bản, log nằm trong `~/.vnc` hoặc
`~/.local/state/tigervnc`.

## Firefox Mac qua Kali

Firefox và profile chạy trên Mac. Chỉ các kết nối web dùng proxy được gửi qua SSH
tới Kali, rồi Kali kết nối website bằng route/VPN của nó:

```text
Firefox Mac → SOCKS5 127.0.0.1:1080 → SSH/Tailscale → Kali → VPN HTB → website lab
```

Trên Kali, kết nối VPN HTB và xác nhận lab đang chạy. Trên Mac:

```bash
proxy_up
```

Lệnh mở SOCKS5 ở nền. Khuyến nghị tạo profile Firefox riêng tên `HTB` bằng
`about:profiles` → Create a New Profile → Launch profile in new browser. Giữ
profile thường làm mặc định. Cấu hình chỉ trong profile HTB:

1. Settings, tìm `proxy`, mở Connection Settings/Configure proxy.
2. Chọn **Manual proxy configuration**.
3. Để trống HTTP Proxy/HTTPS Proxy; SOCKS Host **127.0.0.1**, Port **1080**.
4. Chọn **SOCKS v5**, bật **Proxy DNS when using SOCKS v5**.
5. Trong Settings, tìm **DNS over HTTPS**, chọn **Off** cho profile HTB.

Mở URL của lab trong profile này. Với hostname lab cần mapping thủ công, thêm
IP/hostname do lab cung cấp vào `/etc/hosts` **trên Kali**, vì DNS/hostname được
giải quyết ở đầu Kali. Không đặt subnet HTB hay hostname lab vào `No Proxy For`.

Download từ Firefox này lưu trên Mac. Cookies, extensions, DevTools cũng là của
profile Mac; muốn dùng browser/profile trên Kali thì mở Firefox trong VNC.

Khi xong:

```bash
proxy_down
```

Profile HTB dùng proxy sẽ cần `proxy_up` để truy cập web lại. Profile thường dùng
thiết lập kết nối riêng. Nếu lỗi, kiểm tra `ssh kali whoami`, VPN/khả năng truy cập
lab từ Kali, và setting SOCKS/remote DNS trên Mac.

### Test nhanh trước khi cài VPN HTB

Khi Kali đang chạy, `proxy_up` rồi mở `https://example.com/?test=1` trong profile
HTB. Trang phải tải được. Chạy `proxy_down`, mở `https://example.com/?test=2` và
nhấn Cmd-Shift-R để bỏ cache: profile HTB phải báo lỗi proxy, trong khi profile
Personal vẫn dùng web bình thường. Chạy lại `proxy_up`, tải lại trang HTB phải được.

Phép thử này kiểm tra browser dùng tunnel SOCKS tới Kali theo aliases; route vào
mạng HTB được kiểm tra riêng sau khi Kali có VPN. Firefox vẫn là ứng dụng trên Mac.

Nguồn: [TigerVNC Xvnc](https://tigervnc.org/doc/Xvnc.html),
[OpenSSH dynamic forwarding](https://man.openbsd.org/ssh#D),
[Firefox proxy](https://support.mozilla.org/en-US/kb/connection-settings-firefox),
[Firefox DNS over HTTPS](https://support.mozilla.org/en-US/kb/dns-over-https),
[Firefox profiles](https://support.mozilla.org/en-US/kb/profile-manager-create-remove-switch-firefox-profiles).
