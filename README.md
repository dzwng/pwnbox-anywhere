# Pwnbox Anywhere

Dựng một Kali pwnbox chạy trong VMware trên PC Windows tại nhà, rồi điều khiển từ MacBook ở bất cứ đâu. Một điện thoại Android cũ chạy Tailscale + Termux 24/7 làm relay để Wake-on-LAN bật PC khi nó đang tắt.

Bốn thiết bị cùng một tailnet Tailscale. **Không** mở port trên router, **không** expose SSH/VNC ra Internet.

```text
                                     Tailscale
MacBook ──SSH:8022──> Android relay ──magic packet/LAN──> Windows PC
   │                                                        │
   ├──────────── SSH:22 ─────────────────────────────────> Windows ─ Scheduled Task ─> VMware + Kali
   │
   └──────────── SSH:22 ───────────────────────────────────> Kali VM
                         ├─ terminal
                         ├─ local port-forward cho browser
                         └─ tunnel tới TigerVNC localhost:5901
```

Android chỉ cần để **bật** PC khi PC đang tắt. Khi Windows đã chạy, Mac SSH thẳng vào Windows để bật/tắt VM và shutdown.

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
| `setup-android-termux.sh` | Termux | OpenSSH + `wol`, Termux:Boot script, wake lock |
| `setup-windows.ps1` | Windows PowerShell (Admin) | OpenSSH, SSH key, WoL, Scheduled Task VMware. Có chế độ `-Uninstall` |
| `pwnbox.sh` | Kali | SSH, TigerVNC, VMware guest tools, auto-login. Có `uninstall` |
| `macos-pwnbox.zsh.example` | Mac | Các function `pwnbox_up`, `pwnbox_ssh`, `pwnbox_vnc`, ... |

## Thông tin cần chuẩn bị

Thay placeholder bằng giá trị thật (bỏ dấu `<` `>`).

| Placeholder | Ví dụ | Cách lấy |
|---|---|---|
| `<ANDROID_TS_IP>` | `100.92.138.25` | Tailscale app trên Android |
| `<TERMUX_USER>` | `u0_a350` | `whoami` trong Termux |
| `<WINDOWS_TS_IP>` | `100.83.173.85` | Tailscale app trên Windows |
| `<WINDOWS_USER>` | `hband` | `$env:USERNAME` trong PowerShell |
| `<ETHERNET_NAME>` | `Ethernet` | `Get-NetAdapter -Physical` |
| `<PC_MAC>` | `10:FF:E0:C5:B2:B6` | `Get-NetAdapter -Name "Ethernet"` |
| `<VMX_PATH>` | `D:\Vms\HTB-Kali\kali...vmx` | File `.vmx` của Kali |
| `<KALI_TS_IP>` | `100.x.y.z` | `tailscale ip -4` trên Kali |
| `<KALI_USER>` | `kali` | User tạo lúc cài Kali |

Giữ nguyên các tên mặc định để script/alias khỏi phải sửa: task Windows `Wake Kali VM`; SSH host alias `pwnbox-android` / `pwnbox-windows` / `pwnbox-kali`; VNC display `:1`, port `5901`.

---

# Setup

## 1. Tailscale (cả 4 máy)

Đăng nhập cùng một tailnet trên cả 4 thiết bị ([tailscale.com/download](https://tailscale.com/download)).

- **Android:** cài từ Play Store, đăng nhập, bật Always-on VPN nếu có, tắt battery optimization.
- **Windows:** cài, đăng nhập, reboot và xác nhận tự kết nối. Ghi lại `<WINDOWS_TS_IP>`.
- **Kali / Mac:** `curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up` (Kali) hoặc app (Mac).

Repo dùng OpenSSH bình thường, không phụ thuộc Tailscale SSH.

## 2. Android relay (Termux)

Cài **Termux** và **Termux:Boot** từ **cùng một nguồn** F-Droid hoặc GitHub (không trộn nguồn khác signing key; bản Play Store cũ không dùng được). Mở mỗi app một lần, tắt battery optimization, bật auto-start.

```bash
pkg update && pkg install -y git
git clone https://github.com/dzwng/pwnbox-anywhere.git
cd pwnbox-anywhere
bash setup-android-termux.sh
```

Script cài `openssh` + `wol`, tạo `~/.termux/boot/10-pwnbox-relay`, chạy `termux-wake-lock`, và khởi động `sshd` trên port `8022`. Lần đầu (chưa có SSH key) nó hỏi một password tạm cho `ssh-copy-id`.

Ghi lại `whoami` làm `<TERMUX_USER>`. Reboot Android và xác nhận từ máy khác: `ssh -p 8022 <TERMUX_USER>@<ANDROID_TS_IP>`.

> **Chạy lại về sau:** `git pull` rồi `bash setup-android-termux.sh` — script an toàn để re-run: đã có key thì **bỏ qua** bước hỏi password và **không** kill sshd (chạy được cả khi đang SSH vào từ xa). Thêm `--set-password` nếu muốn đổi password, `--restart-sshd` nếu thực sự cần restart (sẽ rớt phiên SSH hiện tại).

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
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_android -C 'mac-to-android'
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_windows -C 'mac-to-windows'
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_kali    -C 'mac-to-kali'
```

**Cài key vào Android & Kali:**

```bash
ssh-copy-id -i ~/.ssh/pwnbox_android.pub -p 8022 <TERMUX_USER>@<ANDROID_TS_IP>
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
Host pwnbox-android
    HostName <ANDROID_TS_IP>
    User <TERMUX_USER>
    Port 8022
    IdentityFile ~/.ssh/pwnbox_android
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

`ServerAliveInterval/CountMax` giữ kết nối khỏi rớt khi mạng chập chờn. `ControlMaster/Persist/Path` (chỉ Kali — máy hay mở/đóng SSH liên tục) tái dùng một kết nối master để lần sau vào gần như tức thì. Test: `ssh pwnbox-android whoami`, `ssh pwnbox-windows whoami`, `ssh pwnbox-kali whoami` — cả ba không hỏi password.

**Aliases:**

```bash
mkdir -p ~/.config/pwnbox
cp macos-pwnbox.zsh.example ~/.config/pwnbox/aliases.zsh
# sửa 3 dòng đầu: PWNBOX_PC_MAC, PWNBOX_VMRUN, PWNBOX_VMX
echo 'source ~/.config/pwnbox/aliases.zsh' >> ~/.zshrc
source ~/.zshrc
```

---

# Sử dụng

**Bật & vào:**

```bash
pwnbox_up      # WoL → chờ Windows → task Kali → chờ Kali (tự chờ mỗi tầng)
pwnbox_ssh
```

**Browser port-forward** (tool Kali chạy ở `127.0.0.1:8080`):

```bash
ssh -N -L 8080:127.0.0.1:8080 pwnbox-kali      # rồi mở http://127.0.0.1:8080 trên Mac
```

**VNC** (server chỉ listen `127.0.0.1:5901`, bắt buộc qua tunnel):

```bash
pwnbox_vnc          # start VNC + giữ tunnel ở foreground
```

Mở TigerVNC/RealVNC Viewer → `127.0.0.1:5901`. `Ctrl-C` chỉ đóng tunnel, session VNC vẫn chạy để reconnect. Tắt hẳn: `pwnbox_vnc_stop`.

> **Retina bị mờ?** VNC là ảnh bitmap cố định nên khi scale lên màn HiDPI sẽ nhòe. Đặt resolution khớp panel Mac + xem viewer ở 100% (xem [Config](#cấu-hình-vnc)).

**Tắt** (luôn Kali trước, Windows sau — `kali_down` dùng `vmrun stop ... soft`, cần open-vm-tools):

```bash
pwnbox_down
```

---

# Cấu hình

## Cấu hình VNC

Đổi resolution (đặt bằng panel vật lý của Mac để nét nhất, vd MacBook Air 13" = `2560x1664`):

```bash
sudo VNC_RESOLUTION=2560x1664 pwnbox install
pwnbox vnc restart
```

Nếu chữ quá nhỏ ở resolution cao, tăng DPI trong phiên VNC (khoảng 144–168, đừng vọt cao khi resolution còn thấp kẻo phóng to quá):

```bash
xfconf-query -c xsettings -p /Xft/DPI -s 168
```

Đổi VNC password — chạy install, khi được hỏi *"Change it? [y/N]"* gõ `y`; hoặc ép reset:

```bash
sudo pwnbox install --reset-vnc-password
pwnbox vnc restart      # server chỉ nạp password lúc khởi động
```

## SSH: tắt password auth (tùy chọn, nên làm sau khi key đã chạy)

Luôn giữ một SSH session đang mở khi test. Kali:

```bash
printf 'PasswordAuthentication no\n' | sudo tee /etc/ssh/sshd_config.d/99-pwnbox.conf
sudo sshd -t && sudo systemctl reload ssh
```

Windows (Admin): sửa `PasswordAuthentication no` trong `$env:ProgramData\ssh\sshd_config` rồi `Restart-Service sshd`. Termux: đặt `PasswordAuthentication no` trong `$PREFIX/etc/ssh/sshd_config`, `pkill -f '[s]shd'; sshd`.

---

# Uninstall

## Android

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
| Mac không SSH được Android sau reboot | Mở Termux:Boot 1 lần; tắt battery optimization; `~/.termux/boot/10-pwnbox-relay` executable |
| `wol` chạy nhưng PC không bật | Ethernet có dây; BIOS WoL + tắt ErP/Fast Startup; đúng MAC Ethernet; tắt Wi-Fi AP isolation |
| Windows SSH lỗi | `Get-Service sshd`; dùng account password/public key, **không** phải Windows Hello PIN |
| Windows vẫn hỏi password dù đã cài key | Khối `Match Group administrators` trong `sshd_config` bị comment → bỏ comment (chạy lại `-MacPublicKey`) rồi `Restart-Service sshd`. Xem lý do: `Get-WinEvent -LogName OpenSSH/Operational` |
| `kali_up` báo OK nhưng VMware không hiện | Windows đã auto-login? Task principal đúng user + `LogonType Interactive`? |
| VNC `connection refused` | `ss -ltn \| grep 5901` trên Kali; tunnel Mac còn chạy?; `pwnbox vnc restart` |
| VNC ăn password cũ | Có systemd `vncserver@1` giành `:1` → `sudo systemctl disable --now vncserver@1`; xác minh bằng `pgrep -af Xtigervnc` (xem `-PasswordFile`) |

## License

MIT
