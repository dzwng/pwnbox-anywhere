# Pwnbox Anywhere

Dựng một Kali pwnbox chạy trong VMware trên PC Windows tại nhà, rồi điều khiển từ MacBook ở bất cứ đâu. ThinkPad X1 Carbon Gen 8 chạy **Debian 13 XFCE + Tailscale + OpenSSH** 24/7 làm relay để Wake-on-LAN bật PC khi nó đang tắt.

Bốn thiết bị cùng một tailnet Tailscale. **Không** mở port trên router, **không** expose SSH/VNC ra Internet.

```text
                                     Tailscale
MacBook ──SSH:22──> Debian relay ──magic packet/LAN──> Windows PC
   │                                                        │
   ├──────────── SSH:22 ─────────────────────────────────> Windows ─ Scheduled Task ─> VMware + Kali
   │
   └──────────── SSH:22 ───────────────────────────────────> Kali VM
                         ├─ terminal
                         ├─ local port-forward cho browser
                         └─ tunnel tới TigerVNC localhost:5901
```

Debian relay chỉ cần để **bật** PC khi PC đang tắt. Khi Windows đã chạy, Mac SSH thẳng vào Windows để bật/tắt VM và shutdown. Relay tiếp tục chạy khi dùng `pwnbox_down`.

Setup hiện tại: ThinkPad i5-10210U / RAM 8 GB / SSD 256 GB, hostname Linux `debian`, user `zwng`, tên máy trên Tailscale `pwnbox-relay`. Android/Termux là phương án cũ; script vẫn được giữ trong repo, xem [hướng dẫn Android](./android-relay.md).

## Lệnh hằng ngày (trên Mac)

| Lệnh | Việc |
|---|---|
| `pwnbox_up` | Bật cả chuỗi: WoL → chờ Windows → chạy task Kali → chờ Kali |
| `pwnbox_ssh` | SSH vào Kali |
| `pwnbox_vnc` | Bật VNC trên Kali + mở tunnel local `5901` |
| `pwnbox_vnc_stop` | Tắt VNC session trên Kali |
| `pwnbox_down` | Tắt đúng thứ tự: Kali trước, Windows sau |
| `pc_up` / `kali_up` | Từng bước: WoL bật PC / chạy task `Wake Kali VM` |
| `kali_down` / `pc_down` | Từng bước: tắt VM / shutdown Windows |

## File trong repo

| File | Chạy ở đâu | Mục đích |
|---|---|---|
| `debian-relay.md` | Debian + Mac | Runbook relay 24/7: power, Tailscale, SSH key, firewall, locale và WoL |
| `setup-android-termux.sh` | Termux (phương án cũ) | OpenSSH + `wol`, Termux:Boot script, wake lock |
| `setup-windows.ps1` | Windows PowerShell (Admin) | OpenSSH, SSH key, WoL, Scheduled Task VMware. Có chế độ `-Uninstall` |
| `pwnbox.sh` | Kali | SSH, TigerVNC, VMware guest tools, auto-login. Có `uninstall` |
| `macos-pwnbox.zsh.example` | Mac | Các function `pwnbox_up`, `pwnbox_ssh`, `pwnbox_vnc`, ... |

## Thông tin cần chuẩn bị

Thay placeholder bằng giá trị thật (bỏ dấu `<` `>`).

| Placeholder | Ví dụ | Cách lấy |
|---|---|---|
| `<RELAY_TS_IP>` | `100.x.y.z` | `tailscale ip -4` trên Debian; ưu tiên MagicDNS `pwnbox-relay` |
| `<RELAY_USER>` | `zwng` | `whoami` trên Debian |
| `<WINDOWS_TS_IP>` | `100.x.y.z` | Tailscale app trên Windows |
| `<WINDOWS_USER>` | `hband` | `$env:USERNAME` trong PowerShell |
| `<ETHERNET_NAME>` | `Ethernet` | `Get-NetAdapter -Physical` |
| `<PC_MAC>` | `AA:BB:CC:DD:EE:FF` | `Get-NetAdapter -Name "Ethernet"` |
| `<VMX_PATH>` | `D:\Vms\HTB-Kali\kali...vmx` | File `.vmx` của Kali |
| `<KALI_TS_IP>` | `100.x.y.z` | `tailscale ip -4` trên Kali |
| `<KALI_USER>` | `kali` | User tạo lúc cài Kali |

Giữ nguyên các tên mặc định để script/alias khỏi phải sửa: task Windows `Wake Kali VM`; SSH host alias `pwnbox-relay` / `pwnbox-windows` / `pwnbox-kali`; VNC display `:1`, port `5901`.

---

# Setup

## 1. Tailscale (cả 4 máy)

Đăng nhập cùng một tailnet trên cả 4 thiết bị ([tailscale.com/download](https://tailscale.com/download)).

- **Debian relay:** cài Tailscale Linux, đăng nhập và đặt tên máy `pwnbox-relay`; xem [runbook Debian](./debian-relay.md).
- **Windows:** cài, đăng nhập, bật **Run unattended**, reboot và xác nhận tự kết nối. Ghi lại `<WINDOWS_TS_IP>`.
- **Kali / Mac:** `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up` (Kali) hoặc app (Mac).

Repo dùng OpenSSH bình thường, không phụ thuộc Tailscale SSH.

Tắt **device key expiry** cho Debian và Windows để tránh phải re-authenticate khi đang dùng từ xa. Kali VM cố định dùng như remote pwnbox cũng có thể tắt; MacBook/iPhone giữ expiry bật. Đây là thời hạn key của thiết bị đã tham gia tailnet, khác với auth key dùng để enroll. Xem [giải thích và thao tác](./debian-relay.md#3-device-key-expiry).

## 2. Debian relay (ThinkPad 24/7)

Theo [debian-relay.md](./debian-relay.md) để kiểm tra sleep/lid/TLP sau reboot, cài Tailscale, test SSH key rồi harden SSH và test WoL. Trên Debian:

```bash
sudo apt update
sudo apt install -y openssh-server wakeonlan
sudo systemctl enable --now ssh
wakeonlan <PC_MAC>
```

Relay phải cùng LAN/broadcast domain với card Ethernet của PC Windows. Không cần subnet router, exit node hay port forwarding để làm relay: Mac gửi lệnh SSH qua Tailscale, Debian phát magic packet trong LAN.

## 3. Windows

**BIOS/UEFI:** bật virtualization (VT-x/SVM) và Wake-on-LAN (Power On By PCI-E / Resume By LAN); disable ErP/Deep Sleep nếu có (NIC cần còn điện ở S5). WoL tin cậy nhất với **Ethernet có dây**.

**Chuẩn bị:** cài Windows Update + driver NIC, cài VMware Workstation, tạo/import Kali VM với đường dẫn `.vmx` cố định, boot Kali một lần từ console.

**Chạy script** (PowerShell **Run as administrator**, tại thư mục repo):

```powershell
Set-ExecutionPolicy -Scope Process Bypass
Get-NetAdapter -Physical          # lấy tên card mạng
.\setup-windows.ps1 -VmxPath "<VMX_PATH>" -EthernetAdapter "<ETHERNET_NAME>" -DisableFastStartup
```

Chỉ `-VmxPath` và `-EthernetAdapter` là **bắt buộc**; các flag khác đều có default. Script cài OpenSSH + firewall port 22, bật Wake-on-Magic-Packet, tắt Fast Startup (bắt buộc để WoL từ trạng thái shutdown hoạt động), và tạo Scheduled Task `Wake Kali VM` (`LogonType Interactive`, chạy `vmrun start "<VMX>" gui`).

> Nếu chưa từng cài SSH key từ Mac, thêm `-MacPublicKey` — xem [Mac SSH key](#5-mac-ssh-key--config--aliases).

**Auto-logon:** dùng [Sysinternals Autologon](https://learn.microsoft.com/en-us/sysinternals/downloads/autologon) (chạy Admin, điền user + password thật, Enable). Task cần một interactive desktop nên Windows phải vào thẳng desktop; **không** đổi task sang chạy `SYSTEM` (VMware GUI sẽ chạy vô hình).

Kiểm tra khi đã auto-login và VMware đang đóng:

```powershell
schtasks /run /tn "Wake Kali VM"     # VMware GUI phải hiện + Kali boot
```

## 4. Kali

Từ VMware console: hoàn tất cài Kali (user + XFCE/LightDM), `sudo apt update && sudo apt full-upgrade -y`, cài Tailscale (mục 1), ghi lại `<KALI_TS_IP>`.

```bash
git clone https://github.com/dzwng/pwnbox-anywhere.git
cd pwnbox-anywhere
chmod +x pwnbox.sh
sudo ./pwnbox.sh install --enable-autologin
```

Script đảm bảo `openssh-server`, cài `tigervnc-standalone-server` + XFCE startup, `dbus-x11`, `open-vm-tools(-desktop)`, LightDM autologin drop-in, và command `/usr/local/bin/pwnbox`. Nó hỏi VNC password (**6–8 ký tự** — TigerVNC chỉ dùng tối đa 8).

Reboot rồi xác nhận: `pwnbox status`, Kali vào thẳng XFCE, Tailscale + SSH chạy.

> Nếu máy đã có sẵn service VNC cũ (vd systemd `vncserver@1`), **tắt nó** để tránh tranh chấp display `:1`: `sudo systemctl disable --now vncserver@1`. Chỉ để pwnbox quản `:1`.

## 5. Mac: SSH key + config + aliases

**Tạo 3 key riêng** (rotate/revoke từng máy độc lập):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_relay   -C 'mac-to-pwnbox-relay'
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_windows -C 'mac-to-windows'
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_kali    -C 'mac-to-kali'
```

**Cài key vào Debian & Kali:**

```bash
cat ~/.ssh/pwnbox_relay.pub | ssh <RELAY_USER>@pwnbox-relay \
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
ssh-copy-id -i ~/.ssh/pwnbox_kali.pub <KALI_USER>@<KALI_TS_IP>
```

**Cài key vào Windows** (admin account đọc `%ProgramData%\ssh\administrators_authorized_keys`, không phải file user). Copy key trên Mac `pbcopy < ~/.ssh/pwnbox_windows.pub`, rồi trên Windows (Admin):

```powershell
$MacPublicKey = 'ssh-ed25519 AAAA... mac-to-windows'

.\setup-windows.ps1 -VmxPath "D:\Vms\HTB-Kali\kali-linux-2026.1-vmware-amd64.vmx" -EthernetAdapter "Ethernet" -MacPublicKey $MacPublicKey -DisableFastStartup
```

Script cũng tự **bật khối `Match Group administrators`** trong `sshd_config` (kèm `sshd -t` validate) — nếu khối này bị comment thì key có cài vào `administrators_authorized_keys` cũng bị sshd bỏ qua và bắt nhập password.

**`~/.ssh/config`** (rồi `chmod 600 ~/.ssh/config`):

```sshconfig
Host pwnbox-relay
    HostName pwnbox-relay
    User <RELAY_USER>
    IdentityFile ~/.ssh/pwnbox_relay
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host pwnbox-windows
    HostName <WINDOWS_TS_IP>
    User <WINDOWS_USER>
    IdentityFile ~/.ssh/pwnbox_windows
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host pwnbox-kali
    HostName <KALI_TS_IP>
    User <KALI_USER>
    IdentityFile ~/.ssh/pwnbox_kali
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPersist 10m
    ControlPath ~/.ssh/cm-%C
```

`ServerAliveInterval/CountMax` giữ kết nối khỏi rớt khi mạng chập chờn. `ControlMaster/Persist/Path` (chỉ Kali — máy hay mở/đóng SSH liên tục) tái dùng một kết nối master để lần sau vào gần như tức thì. Test: `ssh pwnbox-relay whoami`, `ssh pwnbox-windows whoami`, `ssh pwnbox-kali whoami` — cả ba dùng key thay cho account password (key có passphrase có thể hỏi passphrase).

Nếu MagicDNS chưa resolve, thay `HostName pwnbox-relay` bằng `<RELAY_TS_IP>`. User hiện tại là `zwng`; Linux hostname vẫn có thể là `debian`.

**Aliases:**

```bash
mkdir -p ~/.config/pwnbox
cp macos-pwnbox.zsh.example ~/.config/pwnbox/aliases.zsh
# sửa 3 dòng đầu: PWNBOX_PC_MAC, PWNBOX_VMRUN, PWNBOX_VMX
# nếu cần: PWNBOX_WOL_BROADCAST = broadcast của LAN relay, xem debian-relay.md
echo 'source ~/.config/pwnbox/aliases.zsh' >> ~/.zshrc
source ~/.zshrc
```

**Đang chuyển từ Android:** thêm SSH host/key `pwnbox-relay`, test `ssh pwnbox-relay hostname`, rồi cập nhật bản `~/.config/pwnbox/aliases.zsh` đang dùng (chỉ `git pull` không cập nhật bản đã copy). `pc_up` mới chạy `wakeonlan` qua Debian; giữ MAC/path thực tế của bạn. Test `pc_up` và `pwnbox_up` trước khi gỡ relay Android.

---

# Sử dụng

**Bật & vào:**

```bash
pwnbox_up      # WoL → chờ Windows → task Kali → chờ Kali (tự chờ mỗi tầng)
pwnbox_ssh
```

**Browser port-forward** (tool Kali chạy ở `127.0.0.1:8080` — một service cụ thể trên localhost của Kali):

```bash
ssh -N -L 8080:127.0.0.1:8080 pwnbox-kali      # rồi mở http://127.0.0.1:8080 trên Mac
```

**Lướt web lab (SOCKS proxy)** — để duyệt IP lab (vd HTB `10.129.x.x`, chỉ Kali thấy qua `tun0`) bằng Firefox trên Mac:

```bash
proxy_up        # SOCKS5 127.0.0.1:1080 chạy nền; proxy_down để tắt
```

Trong Firefox cài **FoxyProxy** → SOCKS5, `127.0.0.1:1080`, bật **"Send DNS through SOCKS5"**; đặt pattern `10.10.*`, `10.129.*`, `*.htb` để chỉ proxy dải lab. Host `*.htb` map trong `/etc/hosts` của **Kali** (vì remote DNS). Khác `-L` (một đích cố định), SOCKS cho duyệt **mọi** IP/port Kali thấy mà không sửa lệnh.

**Chuyển file** (dùng lại kết nối `pwnbox-kali`):

```bash
kali_pull '~/htb/box/loot.zip'       # kéo Kali → thư mục hiện tại Mac
kali_push ./exploit.py               # đẩy Mac → home Kali
kali_push ./wl.txt '~/htb/box/'      # đẩy vào thư mục cụ thể trên Kali
```

**Chọn kênh nào cho việc gì:**

| Việc | Kênh |
|---|---|
| Tool CLI (nmap, gobuster, msfconsole...) | `pwnbox_ssh` — terminal thẳng |
| Lướt web lab nhẹ | SOCKS (`proxy_up`) + Firefox Mac |
| Web pentest có Burp | VNC vào Kali (Firefox+Burp wire sẵn) |
| GUI phân tích dữ liệu (BloodHound xem đồ thị, mở `.pcap`) | Chạy **native trên Mac**, `kali_pull` file về |
| GUI cần chạm mạng lab / cần màn hình Kali | VNC |

**VNC** (server chỉ listen `127.0.0.1:5901`, bắt buộc qua tunnel):

```bash
pwnbox_vnc          # start VNC + giữ tunnel ở foreground
```

Mở TigerVNC/RealVNC Viewer → `127.0.0.1:5901`. `Ctrl-C` chỉ đóng tunnel, session VNC vẫn chạy để reconnect. Tắt hẳn: `pwnbox_vnc_stop`.

> **Retina bị mờ?** VNC là ảnh bitmap cố định nên khi scale lên màn HiDPI sẽ nhòe. Đặt resolution khớp panel Mac + xem viewer ở 100%.

**Tắt** (luôn Kali trước, Windows sau — `kali_down` dùng `vmrun stop ... soft`, cần open-vm-tools):

```bash
pwnbox_down
```

---

# Cấu hình

## SSH: tắt password auth (tùy chọn, nên làm sau khi key đã chạy)

Luôn giữ một SSH session đang mở khi test. Kali:

```bash
printf 'PasswordAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/99-pwnbox.conf
sudo sshd -t && sudo systemctl reload ssh
```

Windows (Admin): sửa `PasswordAuthentication no` trong `$env:ProgramData\ssh\sshd_config` rồi `Restart-Service sshd`. Debian relay: xem [harden SSH và firewall](./debian-relay.md#5-harden-ssh-sau-khi-key-hoạt-động).

---

# Uninstall

## Android (relay cũ)

```bash
cd pwnbox-anywhere
bash setup-android-termux.sh uninstall                       # xóa boot script + thả wake lock
bash setup-android-termux.sh uninstall --stop-sshd           # kèm dừng sshd (rớt phiên SSH)
bash setup-android-termux.sh uninstall --stop-sshd --remove-packages   # gỡ luôn openssh + wol
```

| Cờ | Tác dụng |
|---|---|
| (mặc định) | Xóa `~/.termux/boot/10-pwnbox-relay` (không auto-start sshd khi boot) + `termux-wake-unlock` |
| `--stop-sshd` | Kill sshd đang chạy (rớt phiên SSH; nếu không, sshd sống tới khi reboot) |
| `--remove-packages` | `pkg uninstall openssh wol` (mất khả năng SSH vào máy này) |

Mặc định **giữ** openssh/wol, Tailscale và Termux password.

## Kali

```bash
sudo pwnbox uninstall vnc          # xóa VNC session + config do pwnbox tạo
sudo pwnbox uninstall autologin    # xóa LightDM autologin drop-in
sudo pwnbox uninstall all          # cả hai + xóa /usr/local/bin/pwnbox
```

Quy tắc: **không bao giờ** đụng SSH; **không** gỡ VMware Tools/XFCE/LightDM/`dbus-x11`. `tigervnc-standalone-server` chỉ bị purge nếu pwnbox ghi nhận chính nó đã cài package đó (có sẵn từ trước thì giữ nguyên).

## Windows

```powershell
# Gỡ cơ bản: xóa task + Mac key + revert WoL. Giữ OpenSSH để không tự khóa mình.
.\setup-windows.ps1 -Uninstall -EthernetAdapter "<ETHERNET_NAME>" -MacPublicKey $MacPublicKey

# Gỡ sạch mọi thứ script từng thêm (khỏi hỏi xác nhận):
.\setup-windows.ps1 -Uninstall -EthernetAdapter "<ETHERNET_NAME>" -MacPublicKey $MacPublicKey `
    -RestoreFastStartup -RemoveOpenSSH -Force
```

| Cờ | Tác dụng |
|---|---|
| (mặc định) | Xóa task `Wake Kali VM`, gỡ đúng dòng Mac key (giữ key khác), tắt Wake-on-Magic-Packet |
| `-RestoreFastStartup` | Bật lại Fast Startup (`HiberbootEnabled = 1`) |
| `-RemoveOpenSSH` | Stop/disable sshd + xóa firewall rule + gỡ OpenSSH capability |
| `-Force` | Bỏ qua prompt xác nhận |

Mặc định **giữ** OpenSSH, Tailscale và Sysinternals Autologon — gỡ thủ công nếu muốn.

---

# Troubleshooting nhanh

| Triệu chứng | Kiểm tra |
|---|---|
| Mac không SSH được Debian sau reboot/gập nắp | `systemctl is-active ssh tailscaled`; sleep target masked; logind/XFCE lid = ignore/Do nothing; Wi-Fi vẫn kết nối |
| `LC_CTYPE: cannot change locale (UTF-8)` | SSH đã kết nối; Mac gửi locale Debian không có. Xem [cách sửa locale](./debian-relay.md#8-cảnh-báo-locale-khi-ssh-từ-mac) |
| `wakeonlan` chạy nhưng PC không bật | Ethernet có dây; BIOS WoL + tắt ErP/Fast Startup; đúng MAC Ethernet; cùng broadcast domain; thử `PWNBOX_WOL_BROADCAST`; tắt Wi-Fi AP isolation |
| Windows SSH lỗi | `Get-Service sshd`; dùng account password/public key, **không** phải Windows Hello PIN |
| Windows vẫn hỏi password dù đã cài key | Khối `Match Group administrators` trong `sshd_config` bị comment → bỏ comment (chạy lại `-MacPublicKey`) rồi `Restart-Service sshd`. Xem lý do: `Get-WinEvent -LogName OpenSSH/Operational` |
| `kali_up` báo OK nhưng VMware không hiện | Windows đã auto-login? Task principal đúng user + `LogonType Interactive`? |
| VNC `connection refused` | `ss -ltn \| grep 5901` trên Kali; tunnel Mac còn chạy?; `pwnbox vnc restart` |
| VNC ăn password cũ | Có systemd `vncserver@1` giành `:1` → `sudo systemctl disable --now vncserver@1`; xác minh bằng `pgrep -af Xtigervnc` (xem `-PasswordFile`) |

## License

MIT
