# Pwnbox Anywhere v2

Bật, tắt và chọn **Windows 11 / Kali dual boot / Kali VMware** trên PC ở nhà từ
MacBook hoặc dashboard qua Tailscale. ThinkPad Debian chạy 24/7 nhận lệnh điều khiển;
Mac kết nối trực tiếp tới từng Kali để dùng SSH, GUI và browser lab.

**Windows là OS mặc định.** Khi yêu cầu Kali, project chọn Kali cho một lần boot.
Windows và Kali dual boot dùng chung PC, nên chỉ một OS host chạy tại một thời điểm.
Kali VMware là guest chạy cùng Windows; không chạy đồng thời với Kali dual boot.

| Môi trường | Bật/chọn | Dừng | SSH trên Mac |
|---|---|---|---|
| Windows | `pwnbox windows` | `pwnbox off` — tắt cả PC | `ssh windows` |
| Kali dual boot | `pwnbox kali` | `pwnbox off` — tắt cả PC | `ssh kali` |
| Kali VMware | `pwnbox vm-start` | `pwnbox vm-stop` — chỉ guest | `ssh kali-vm` |

## Web Control Center

Dashboard tự host trên ThinkPad cho iPhone/laptop qua Tailscale: bật/chọn OS,
shutdown, theo dõi tiến trình và lịch sử, sức khỏe ThinkPad và CPU/RAM/Disk/GPU/VRAM
desktop. Metrics tải cập nhật mỗi 5 giây khi trang hoạt động. Hướng dẫn cài,
demo local và giới hạn driver: [Control Center](docs/control-center.md).

Dashboard cũng có **Kali VMware** với Start / Stop VM only, độc lập **Kali dual boot**.
`pwnbox vm-start` bật/chọn Windows rồi chạy VM; `pwnbox vm-stop` chỉ dừng guest,
giữ Windows. Config, SSH key/alias và VNC/SOCKS tách riêng. Phục hồi HTB-Kali cũ,
script theo từng máy và hướng dẫn key: [VMware + dual boot](docs/vmware.md).
Khi profile VMware đã bật, controller yêu cầu guest được xác minh **STOPPED** trước
khi chuyển Windows sang Kali, reboot hoặc tắt Windows. Thao tác host và guest dùng
chung khóa; history/xác nhận/CSRF cũng áp dụng cho VM. Metrics desktop là của OS host;
trạng thái guest được kiểm tra riêng. Mục **Websites on ThinkPad** giữ các link HTTPS
Serve/site/course đang có, không đổi route hay nội dung website.

## Cheatsheet — chạy trên Mac

Các lệnh dưới dùng sau khi đã [setup dual boot](docs/setup.md),
[setup VMware nếu cần](docs/vmware.md) và source aliases. Các helper không có hậu tố
`vm` tiếp tục dành cho Kali dual boot.
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

### Kali VMware: điều khiển và truy cập riêng

| Lệnh trên Mac | Tác dụng |
|---|---|
| `pwnbox vm-status` | Xem trạng thái guest, độc lập `pwnbox status` của host |
| `pwnbox vm-doctor` | Kiểm tra profile, inventory Windows và guest SSH |
| `pwnbox vm-start` / `pwnbox_vm_up` | Bật/chọn Windows nếu cần, gọi task rồi chờ guest SSH |
| `pwnbox vm-stop` / `pwnbox_vm_down` | Shutdown sạch riêng guest, giữ Windows |
| `ssh kali-vm` / `pwnbox vm-ssh` | Shell trực tiếp tới node Tailscale của guest |
| `pwnbox_vm_vnc` | Mở/dùng lại desktop guest và tunnel nền tại `127.0.0.1:5902` |
| `open vnc://127.0.0.1:5902` | Mở Screen Sharing tới guest |
| `pwnbox_vm_vnc_disconnect` | Đóng tunnel, giữ desktop guest |
| `pwnbox_vm_vnc_stop` | Kết thúc phiên VNC và ứng dụng trong phiên; guest vẫn bật |
| `proxy_vm_up` / `proxy_vm_down` | Bật/tắt SOCKS guest tại `127.0.0.1:1081` trên Mac |
| `kali_vm_pull '~/htb/loot.zip' .` | Tải file guest về Mac |
| `kali_vm_push ./exploit.py '~/htb/'` | Gửi file Mac vào guest |

Windows có VM đang chạy vẫn hiện **WINDOWS**; trạng thái thẻ VMware là **RUNNING**.
Guest không SSH được không có nghĩa đã tắt. `vm-stop` không bật/chuyển OS host và
không fallback hard power-off; xem console VMware nếu guest mất SSH.

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

Với VMware, tạo profile Firefox **HTB-VM trên Mac**, dùng `proxy_vm_up` và SOCKS v5
`127.0.0.1:1081`. Profile **HTB** cũ tiếp tục dùng dual boot qua cổng `1080`.
Cấu hình trong Firefox Settings: tìm **proxy** → Manual proxy configuration,
để trống HTTP/HTTPS Proxy, bật proxy DNS qua SOCKS v5. Trong Privacy & Security,
đặt DNS over HTTPS thành Off. Không cần chỉnh proxy toàn hệ thống Mac.

Test trước khi có VPN: bật `proxy_vm_up`, mở `https://example.com/?proxy-test=1`
trong HTB-VM; chạy `proxy_vm_down` rồi mở URL mới với `?proxy-test=2` phải lỗi proxy;
bật lại và mở `?proxy-test=3` phải tải được. Dùng Cmd+Shift+R để bỏ cache nếu cần.
Phép thử này xác minh browser dùng tunnel. Để xác minh lab, bật VPN **trong guest**
và mở website lab từ HTB-VM; mapping `.htb` cần đặt trong `/etc/hosts` của guest.

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
Đặc biệt **không dùng `kali_down`/`pwnbox_down` để dừng riêng VM**; dùng `pwnbox vm-stop`.

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

Làm việc với VMware, giữ Windows chạy:

```zsh
pwnbox vm-start
ssh kali-vm
# Từ terminal Mac khác, nếu cần GUI hoặc browser:
pwnbox_vm_vnc
open vnc://127.0.0.1:5902
proxy_vm_up
```

Kết thúc: `proxy_vm_down`, ngắt VNC bằng `pwnbox_vm_vnc_disconnect`; khi muốn tắt
guest, lưu công việc rồi chạy `pwnbox vm-stop`. Muốn chuyển sang bare metal: dừng
guest trước rồi `pwnbox kali`.

## Hệ thống hoạt động thế nào?

```text
Điều khiển PC:  Mac → SSH/Tailscale → ThinkPad → WoL / SSH trong LAN → PC
Truy cập Kali:  Mac → Tailscale trực tiếp → Kali SSH / VNC / SOCKS
GUI Windows:   Mac → AnyDesk → Windows
VMware:        ThinkPad → Windows SSH → interactive task → Kali VMware
Truy cập VM:   Mac → Tailscale trực tiếp → guest SSH / VNC / SOCKS
```

ThinkPad giữ logic bật máy, nhận diện OS và chờ chuyển OS. Phiên SSH/VNC/SOCKS
của Mac đi trực tiếp tới Kali. Tailscale cài trên Mac, ThinkPad, Windows và Kali;
Windows/Kali có tên và IP Tailscale riêng. Node của OS không chạy sẽ offline.
Guest VMware cũng có node riêng (`kali-vmware`), key và host-key alias riêng;
không thay địa chỉ `KALI_HOST` của bare metal bằng địa chỉ guest.

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

### Thêm VMware vào hệ thống đã có dual boot

Không cần cài lại dual boot, WoL hay SSH Windows. Giữ key hiện có; thêm hai key
dành riêng cho VM: `pwnbox_control_kali_vm` trên ThinkPad và `pwnbox_kali_vm` trên Mac.
Private key ở lại máy tạo key; chỉ chuyển `.pub` tới guest.

1. Mở guest cũ một lần trên Windows; ghi lại `whoami`, `tailscale ip -4` và host
   fingerprint trong guest. Controller dùng `.vmx`, không dùng ổ đĩa `.vmdk`.
2. Windows PowerShell **Administrator**: chạy `setup/setup-vmware-windows.ps1`
   với `-VmxPath` và `-WindowsUser` đúng. Task mới là **Pwnbox Kali VMware**;
   không có trigger tự bật VM mỗi lần Windows boot. Task cũ được giữ để đối chiếu.
3. Cập nhật ThinkPad bằng gói source từ Windows:

   ```powershell
   Set-Location D:\Code\pwnbox-anywhere
   python setup/build-release.py
   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup\update-thinkpad-from-windows.ps1
   ```

   Mặc định relay là `zwng@pwnbox-relay`; thay bằng `-Relay user@hostname` nếu khác.
   Script hỏi SSH/sudo trong terminal, xác minh checksum và backup code. Gói nằm trong
   `.local/releases`, không đưa vào Git. Nếu code đã có trên ThinkPad, dùng
   `bash setup/update-web.sh`. Mật khẩu/history/Serve hiện có được giữ.
4. ThinkPad, bằng user controller **không sudo**: chạy
   `bash setup/prepare-vmware-thinkpad.sh VM_USER` với user guest thật.
   Mac tạo interactive key VM riêng. Trong guest, chạy
   `sudo bash setup/setup-kali-vm.sh VM_USER /path/thinkpad-vm.pub /path/mac-vm.pub`.
5. Xác minh fingerprint và marker `PWNBOX_KALI_VM` từ ThinkPad, rồi điền user/địa chỉ
   thật vào `~/.config/pwnbox/vmware.conf`, đặt `VM_ENABLED=true`. Không sửa profile
   `pwnbox.conf` của dual boot. Chưa có profile thì dashboard hiện Not configured.
6. Mac merge [SSH config VM](config/ssh-macos-vmware.conf.example), cập nhật/source
   aliases mới. Alias `kali-vm` trỏ guest; `kali` giữ bare metal. GUI guest cài bằng
   `sudo bash pwnbox.sh install --vmware-tools`, từ user tương tác trong guest.
7. Test `vm-stop` giữ Windows, `vm-start` chờ đúng guest; thử cold boot sau khi
   Windows autologon/interactive login đã sẵn sàng. Task GUI cần Windows user logged
   in; lock màn hình được, sign out thì không chạy. Không cần autologin desktop Kali
   để dùng VNC.

**`VM_USER`, `TEN_USER_VM`, `IP_TAILSCALE_VM` và `/path/...` trong hướng dẫn là chỗ cần
thay bằng giá trị thật**, không paste nguyên vào SSH config. Trên Mac có thể đối chiếu
profile đã cấu hình trên ThinkPad bằng:

```zsh
ssh pwnbox-relay "grep -E '^VM_(HOST|USER)=' ~/.config/pwnbox/vmware.conf"
ssh -G kali-vm | awk '/^(hostname|user|identityfile|hostkeyalias) /'
```

Runbook theo từng máy, key/fingerprint và xử lý lỗi:
[VMware + dual boot](docs/vmware.md). Không chạy legacy installer/uninstall để phục hồi.
Clipboard qua cửa sổ VMware và clipboard qua VNC là hai đường khác nhau; VNC tạo
desktop riêng. Khi gặp lỗi paste, xác định đang dùng console VMware hay VNC trước.

## Kiểm thử và cập nhật

Chạy từ repository bằng user thường:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash tests/test-orchestration.sh
bash tests/test-vmware.sh
bash tests/test-kali-vm-control.sh
bash tests/test-macos-vmware.sh
python3 tests/test-wol.py
bash tests/test-vnc-reconnect.sh
node tests/test-dashboard.cjs
```

Tests dùng endpoint giả và UDP loopback. Hardware test có reboot/shutdown/WoL:
đọc [acceptance matrix](docs/dualboot.md) trước khi chạy.
Kết quả workstation đã setup: [verification](docs/verification.md).
Python tests cho helper/deployment Windows dùng PowerShell mock và được skip trên
Linux. Git Bash cần `PWNBOX_TEST_PYTHON` trỏ Python thật nếu `python3` là Store alias;
kiểm tra native `flock` chạy trên Debian, Git Bash dùng shim. Kết quả xác minh dual
boot trước đây không thay cho acceptance test VMware trên máy thật.

`git pull` chỉ cập nhật repository. CLI đã cài và aliases đã copy cần cập nhật riêng
theo [setup](docs/setup.md). VMware/Android cũ được giữ ở [legacy](docs/legacy.md);
không chạy legacy uninstall để dọn v2.

MIT License.
