# Pwnbox Anywhere v2

Bật, tắt và chuyển giữa **Windows 11 / Kali dual boot** trên PC ở nhà từ MacBook.
ThinkPad Debian chạy 24/7 nhận lệnh điều khiển; Mac kết nối trực tiếp tới OS đang chạy
để dùng SSH, GUI và browser lab.

**Windows là OS mặc định.** Khi yêu cầu Kali, project chọn Kali cho một lần boot.
Windows và Kali dùng chung PC, nên chỉ một OS chạy tại một thời điểm.

## Cheatsheet — chạy trên Mac

Các lệnh dưới dùng sau khi đã [setup](docs/setup.md) và source aliases.
**Lưu công việc trên PC trước khi chuyển OS hoặc tắt máy.**

### Điều khiển PC

| Lệnh | Dùng khi bạn muốn |
|---|---|
| `pwnbox status` | Xem PC đang chạy Windows, Kali, chuyển OS, tắt hay chưa xác định |
| `pwnbox wake` | Bật PC bằng WoL nếu cần, chờ OS sẵn sàng |
| `pwnbox windows` | Bật/chuyển sang Windows; đã Windows thì giữ nguyên |
| `pwnbox kali` | Bật/chuyển sang Kali; đã Kali thì giữ nguyên |
| `pwnbox off` | Shutdown toàn bộ PC bằng lệnh của OS đang chạy |
| `pwnbox doctor` | Xem config, endpoint và trạng thái để chẩn đoán |
| `pwnbox help` | Xem danh sách lệnh |
| `ssh kali` hoặc `pwnbox ssh` | Mở shell Kali trực tiếp qua Tailscale |
| `ssh windows` | Mở shell Windows trực tiếp qua Tailscale |
| `ssh pwnbox-relay` | Mở shell ThinkPad |

### GUI Kali: TigerVNC

| Lệnh | Tác dụng |
|---|---|
| `pwnbox_vnc` | Mở/dùng lại desktop Kali và SSH tunnel chạy nền |
| `open vnc://127.0.0.1:5901` | Mở Screen Sharing trên Mac, kết nối desktop VNC |
| `pwnbox_vnc_disconnect` | Đóng tunnel, **giữ desktop và ứng dụng đang chạy** |
| `pwnbox_vnc_stop` | **Đóng desktop VNC và các ứng dụng trong phiên**, rồi đóng tunnel |
| `ssh kali 'pwnbox-kali vnc status'` | Xem các phiên VNC đang chạy trên Kali |

`disconnect` dùng khi tạm nghỉ; gọi `pwnbox_vnc` để quay lại phiên cũ.
`stop` dùng khi làm xong; lần sau sẽ có desktop mới. Cả hai đều để Kali tiếp tục bật.
VNC tạo phiên XFCE riêng. GUI Windows dùng **AnyDesk** hiện có.

### Browser lab: Firefox Mac qua Kali

| Lệnh | Tác dụng |
|---|---|
| `proxy_up` | Mở SOCKS5 trên Mac tại `127.0.0.1:1080`, kết nối qua SSH tới Kali |
| `proxy_down` | Đóng tunnel SOCKS; không dừng Kali hay VPN |

Trong profile Firefox **HTB** trên Mac, đặt SOCKS v5 `127.0.0.1:1080`, bật
**Proxy DNS when using SOCKS v5**, để trống HTTP/HTTPS Proxy và đặt DoH **Off**.
VPN HTB chạy trên Kali; hostname lab cần mapping thì thêm vào `/etc/hosts` trên Kali.

```text
Firefox Mac → SOCKS5 → SSH/Tailscale → Kali → VPN HTB → website lab
```

Firefox, cookies và downloads vẫn ở Mac. Chi tiết profile, DNS và test không cần VPN:
[GUI và browser](docs/gui-and-browser.md).

### Chuyển file và tunnel dịch vụ

| Lệnh | Tác dụng |
|---|---|
| `kali_pull '~/htb/loot.zip' .` | Tải file Kali về thư mục hiện tại trên Mac |
| `kali_push ./exploit.py '~/htb/'` | Gửi file Mac vào thư mục đã có trên Kali |
| `ssh -N -L 127.0.0.1:8080:127.0.0.1:8080 kali` | Tunnel một dịch vụ Kali ở port 8080, ví dụ Burp |

`kali_pull` / `kali_push` hỗ trợ thư mục. Tunnel port 8080 chạy ở foreground:
giữ terminal mở, Ctrl-C đóng tunnel đó.

### Kiểm tra nhanh

| Lệnh | Kiểm tra |
|---|---|
| `ssh kali whoami` | Đúng user Kali, SSH hoạt động |
| `ssh windows whoami` | Đúng user Windows, SSH hoạt động |
| `ssh -G kali` | HostName/User/key mà SSH trên Mac sẽ dùng |
| `tailscale status` | Node nào online; Windows/Kali là hai node riêng |
| `tailscale ping pwnbox-kali` | Đường Tailscale tới Kali; thay tên nếu node dùng tên khác |

### Aliases cũ

| Alias | Tương đương v2 |
|---|---|
| `pc_up` | `pwnbox windows` |
| `kali_up`, `pwnbox_up` | `pwnbox kali` |
| `pc_down`, `kali_down`, `pwnbox_down` | **`pwnbox off` — tắt toàn bộ PC** |
| `pwnbox_ssh` | `pwnbox ssh` |

Ưu tiên các lệnh `pwnbox ...` để tránh nhầm với cách điều khiển VMware trước đây.

## Ví dụ dùng hằng ngày

Vào Kali làm việc:

```zsh
pwnbox kali
ssh kali
```

Mở tool GUI từ terminal khác trên Mac:

```zsh
pwnbox_vnc
open vnc://127.0.0.1:5901
```

Khi chỉ cần website lab, chạy `proxy_up` rồi dùng Firefox profile HTB.
Dùng xong, `proxy_down` đóng proxy; `pwnbox_vnc_disconnect` giữ phiên GUI để quay lại.

## Hệ thống hoạt động thế nào?

```text
Điều khiển PC:  Mac → SSH/Tailscale → ThinkPad → WoL / SSH trong LAN → PC
Truy cập Kali:  Mac → Tailscale trực tiếp → Kali SSH / VNC / SOCKS
GUI Windows:   Mac → AnyDesk → Windows
```

ThinkPad giữ logic bật máy, nhận diện OS và chờ chuyển OS. Phiên SSH/VNC/SOCKS
của Mac đi trực tiếp tới Kali. Tailscale cài trên Mac, ThinkPad, Windows và Kali;
Windows/Kali có tên và IP Tailscale riêng. Node của OS không chạy sẽ offline.

WoL bật nguồn; BootNext/bootsequence chọn OS cho một lần boot. Controller dùng IP
LAN ổn định: đặt DHCP reservation cho ThinkPad và PC. Xem [kiến trúc](docs/architecture.md).

### Đọc trạng thái

| Status | Nghĩa là |
|---|---|
| `WINDOWS` / `KALI` | Endpoint SSH đã xác minh đúng OS |
| `TRANSITIONING` | Đang trong thời gian chờ một lần bật/chuyển/tắt do controller khởi tạo |
| `OFF` | Suy luận sau shutdown đã xác nhận, LAN còn hoạt động và PC không phản hồi |
| `UNKNOWN` | Chưa đủ bằng chứng: có thể PC tắt, mất mạng hoặc SSH lỗi |

`UNKNOWN` khi PC đang tắt có thể bình thường; `pwnbox wake` sẽ gửi WoL rồi kiểm tra
lại. Khi lệnh thất bại, dùng `pwnbox doctor` và [troubleshooting](docs/troubleshooting.md).

## Cài đặt lần đầu

1. Chuẩn bị dual boot, Windows mặc định và WoL: [UEFI/dual boot](docs/dualboot.md).
2. Cài controller trên ThinkPad, endpoint Windows/Kali, config LAN và các key:
   [runbook setup](docs/setup.md), [SSH](docs/ssh.md), [ThinkPad 24/7](debian-relay.md).
3. Cài Tailscale trên từng OS: [Tailscale](docs/tailscale.md).
4. Trên Mac, merge [SSH config mẫu](config/ssh-macos.conf.example) rồi cài aliases:

```zsh
mkdir -p ~/.config/pwnbox
cp macos-pwnbox.zsh.example ~/.config/pwnbox/aliases.zsh
# Thêm một lần vào ~/.zshrc:
# source ~/.config/pwnbox/aliases.zsh
source ~/.config/pwnbox/aliases.zsh
```

5. Nếu dùng GUI Kali, chạy `sudo bash pwnbox.sh install` trên Kali từ user tương tác.
   Hướng dẫn viewer và Firefox: [GUI/browser](docs/gui-and-browser.md).

Automation key ThinkPad và interactive key Mac là các key riêng. Xác minh host
fingerprint tại console; giữ private key/config riêng ngoài Git. Truy cập SSH/VNC
qua Tailscale và tunnel, không mở các cổng này ra Internet trên router.

## Kiểm thử và cập nhật

Chạy từ repository bằng user thường:

```bash
bash tests/test-orchestration.sh
python3 tests/test-wol.py
bash tests/test-vnc-reconnect.sh
```

Tests dùng endpoint giả và UDP loopback. Hardware test có reboot/shutdown/WoL:
đọc [acceptance matrix](docs/dualboot.md) trước khi chạy.
Kết quả workstation đã setup: [verification](docs/verification.md).

`git pull` chỉ cập nhật repository. CLI đã cài và aliases đã copy cần cập nhật riêng
theo [setup](docs/setup.md). VMware/Android cũ được giữ ở [legacy](docs/legacy.md);
không chạy legacy uninstall để dọn v2.

MIT License.
