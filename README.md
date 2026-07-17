# Pwnbox Anywhere — runbook clean install từ A đến Z

Tài liệu này ghi lại toàn bộ cách dựng một Kali pwnbox tại nhà và điều khiển từ MacBook. Nó giả định cả bốn thiết bị đều vừa clean install:

- PC Windows 11 chạy VMware Workstation.
- Kali Linux nằm trong VMware.
- MacBook là máy điều khiển từ xa.
- Android cũ chạy Tailscale + Termux 24/7, làm Wake-on-LAN relay.

Tất cả thiết bị đăng nhập cùng một tailnet Tailscale. Không mở port trên router và không expose SSH/VNC ra Internet.

## 1. Kết quả cuối cùng

```text
                                     Tailscale
MacBook ──SSH:8022──> Android relay ──magic packet/LAN──> Windows PC
   │                                                        │
   ├──────────── SSH:22 ─────────────────────────────────────┤
   │                                                        └─ Scheduled Task
   │                                                           mở VMware + Kali
   │
   └──────────── SSH:22 ───────────────────────────────────> Kali VM
                         ├─ terminal
                         ├─ local port-forward cho browser
                         └─ tunnel tới TigerVNC localhost:5901
```

Các lệnh cuối cùng trên Mac:

| Lệnh | Việc thực hiện |
|---|---|
| `pc_up` | SSH vào Android và gửi WoL packet tới PC |
| `kali_up` | SSH vào Windows và chạy Scheduled Task `Wake Kali VM` |
| `pwnbox_up` | Chạy `pc_up`, chờ Windows, chạy `kali_up`, chờ Kali |
| `pwnbox_ssh` | SSH vào Kali |
| `pwnbox_vnc` | Bật VNC trên Kali và mở tunnel local port 5901 |
| `pwnbox_vnc_stop` | Tắt VNC session trên Kali |
| `kali_down` | `vmrun stop ... soft`, sau đó đóng VMware GUI |
| `pc_down` | Shutdown Windows qua SSH |
| `pwnbox_down` | Chạy `kali_down`, sau đó `pc_down` |

Android chỉ cần thiết để **bật** PC khi PC đang tắt. Khi Windows đang chạy, Mac SSH trực tiếp vào Windows để bật/tắt VM và shutdown PC.

## 2. File trong repo

| File | Chạy ở đâu | Mục đích |
|---|---|---|
| `setup-android-termux.sh` | Termux | Cài OpenSSH + `wol`, tạo Termux:Boot script, giữ wake lock |
| `setup-windows.ps1` | Windows PowerShell Administrator | Cài OpenSSH, cấu hình SSH key, WoL và Scheduled Task VMware |
| `pwnbox.sh` | Kali | Cài SSH, TigerVNC, VMware guest tools và cấu hình Kali auto-login |
| `macos-pwnbox.zsh.example` | Mac | Các function `pc_up`, `kali_up`, `pwnbox_up`, shutdown và VNC |

`pwnbox.sh` cố ý không cài hoặc quản lý tmux. Nếu muốn dùng, bạn tự cài/chạy sau khi SSH vào Kali.

## 3. Chuẩn bị thông tin

Trong tài liệu, thay toàn bộ placeholder sau bằng giá trị thật. Không giữ dấu `<` và `>`.

| Placeholder | Ví dụ | Cách lấy |
|---|---|---|
| `<ANDROID_TS_IP>` | `100.92.138.25` | Tailscale app trên Android |
| `<TERMUX_USER>` | `u0_a350` | Chạy `whoami` trong Termux |
| `<WINDOWS_TS_IP>` | `100.83.173.85` | Tailscale app trên Windows |
| `<WINDOWS_USER>` | `hband` | Chạy `$env:USERNAME` trong PowerShell |
| `<ETHERNET_NAME>` | `Ethernet` | `Get-NetAdapter -Physical` |
| `<PC_MAC>` | `10:FF:E0:C5:B2:B6` | `Get-NetAdapter -Name "Ethernet"` |
| `<VMX_PATH>` | `D:\Vms\HTB-Kali\kali-linux-2026.1-vmware-amd64.vmx` | File `.vmx` của Kali |
| `<KALI_TS_IP>` | `100.x.y.z` | `tailscale ip -4` trên Kali |
| `<KALI_USER>` | `kali` | User tạo lúc cài Kali |

Nên giữ nguyên các tên sau để script/alias không phải sửa nhiều:

- Windows Scheduled Task: `Wake Kali VM`
- SSH host aliases trên Mac: `pwnbox-android`, `pwnbox-windows`, `pwnbox-kali`
- VNC display: `:1`, local port `5901`

## 4. Cài Tailscale trên cả bốn thiết bị

Đăng nhập cùng một tài khoản/tailnet trên cả bốn thiết bị. Trang tải chính thức: [tailscale.com/download](https://tailscale.com/download).

### Android

1. Cài Tailscale từ Play Store hoặc nguồn chính thức.
2. Đăng nhập vào tailnet.
3. Trong Android Settings → VPN → Tailscale, bật **Always-on VPN** nếu ROM hỗ trợ.
4. Tắt battery optimization cho Tailscale.
5. Cho phép chạy nền/auto-start và lock app trong recent apps nếu ROM có các tùy chọn này.

### Windows 11

1. Cài Tailscale.
2. Đăng nhập cùng tailnet.
3. Reboot và kiểm tra Tailscale tự kết nối trước khi làm bước tiếp theo.
4. Ghi lại `<WINDOWS_TS_IP>`.

### Kali

Sau khi Kali đã có Internet:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4
```

### MacBook

1. Cài Tailscale cho macOS.
2. Đăng nhập cùng tailnet.
3. Xác nhận Mac nhìn thấy ba node còn lại trong Tailscale app.

Tailscale chỉ vận chuyển traffic giữa các máy. Repo sử dụng OpenSSH bình thường, không phụ thuộc tính năng Tailscale SSH.

## 5. Android relay: Termux + SSH + WoL

### 5.1 Cài đúng bộ Termux

Cài **Termux** và **Termux:Boot** từ cùng một nguồn F-Droid hoặc GitHub. Không trộn APK/plugin từ các nguồn có signing key khác nhau. Bản Termux Play Store cũ không được dùng.

Nguồn tham khảo chính thức:

- [Termux installation](https://github.com/termux/termux-app#installation)
- [Termux:Boot](https://github.com/termux/termux-boot)

Sau khi cài:

1. Mở Termux ít nhất một lần.
2. Mở app Termux:Boot ít nhất một lần. Đây là bước bắt buộc để Android cho nó nhận boot event.
3. Tắt battery optimization cho Termux và Termux:Boot.
4. Bật auto-start/background activity nếu ROM yêu cầu.
5. Lock Termux và Tailscale trong recent apps.

### 5.2 Chạy bootstrap script

Trong Termux:

```bash
pkg update
pkg install -y git
git clone https://github.com/dzwng/pwnbox-anywhere.git
cd pwnbox-anywhere
bash setup-android-termux.sh
```

Script sẽ:

- update Termux packages;
- cài `openssh` và `wol`;
- tạo `~/.termux/boot/10-pwnbox-relay`;
- chạy `termux-wake-lock`;
- yêu cầu tạo password tạm để Mac chạy `ssh-copy-id` lần đầu;
- khởi động `sshd` trên port mặc định `8022`.

Kiểm tra:

```bash
whoami
ss -ltn | grep 8022
ps -ef | grep '[s]shd'
ls -l ~/.termux/boot/10-pwnbox-relay
```

Ghi lại kết quả `whoami` làm `<TERMUX_USER>`.

Termux:Boot script sử dụng đúng flow được tài liệu chính thức khuyến nghị: gọi `termux-wake-lock` rồi `sshd` sau mỗi lần Android boot.

### 5.3 Kiểm tra Android sống sau reboot

Reboot Android, unlock máy một lần nếu ROM yêu cầu, đợi Tailscale kết nối rồi kiểm tra từ một thiết bị khác:

```bash
ssh -p 8022 <TERMUX_USER>@<ANDROID_TS_IP>
```

Ở giai đoạn này có thể login bằng Termux password. SSH key sẽ được cài ở phần MacBook.

## 6. Windows 11: BIOS, WoL, VMware, SSH và auto-logon

### 6.1 Tạo Windows account

Khuyến nghị dùng một local administrator account có password thật, ví dụ `hband`:

- Windows OpenSSH dùng password của account, không dùng Windows Hello PIN.
- Scheduled Task Interactive và Sysinternals Autologon dùng cùng account này.
- Không để account không có password.

### 6.2 Bật virtualization và WoL trong BIOS/UEFI

Tên option khác nhau theo mainboard. Bật các mục tương đương:

- Intel VT-x/VT-d hoặc AMD SVM/IOMMU.
- Wake on LAN / Power On By PCI-E / Resume By LAN.
- Cho phép NIC nhận nguồn ở trạng thái S5/shutdown.

Nếu có `ErP`, `Deep Sleep` hoặc option cắt toàn bộ nguồn cho PCI-E khi shutdown, hãy disable vì NIC cần còn điện để nhận magic packet.

WoL đáng tin cậy nhất với **Ethernet có dây**. Android có thể ở Wi-Fi nhưng router/AP phải cho Wi-Fi client gửi broadcast tới Ethernet LAN; tắt AP/client isolation nếu đang bật.

### 6.3 Cài Windows, driver và VMware

1. Cài đầy đủ Windows Update.
2. Cài driver chipset và Ethernet từ hãng mainboard/NIC.
3. Cài VMware Workstation.
4. Tạo thư mục VM cố định, ví dụ `D:\Vms\HTB-Kali`.
5. Tạo/import Kali VM và giữ đường dẫn `.vmx` ổn định.

Gợi ý tài nguyên ban đầu:

- 4 vCPU.
- 8 GB RAM nếu PC đủ RAM; giảm còn 4 GB nếu cần.
- 80 GB disk hoặc hơn.
- Network Adapter: NAT.
- Disable `Accelerated 3D graphics` nếu gặp lỗi display; đây cũng là cấu hình Kali khuyến nghị trong [Kali VMware guest guide](https://www.kali.org/docs/virtualization/install-vmware-guest-vm/).

Boot và hoàn tất cài Kali một lần từ VMware console trước khi tạo Scheduled Task.

### 6.4 Cấu hình Windows bằng script

Clone repo trên Windows hoặc copy folder này sang PC. Mở PowerShell bằng **Run as administrator**:

```powershell
cd D:\Code\pwnbox-anywhere
Set-ExecutionPolicy -Scope Process Bypass
Get-NetAdapter -Physical
```

Chọn đúng Ethernet adapter, sau đó chạy:

```powershell
.\setup-windows.ps1 `
    -VmxPath "<VMX_PATH>" `
    -EthernetAdapter "<ETHERNET_NAME>" `
    -WindowsUser "$env:COMPUTERNAME\<WINDOWS_USER>" `
    -DisableFastStartup
```

Script sẽ:

- cài Windows OpenSSH Server capability;
- enable/start service `sshd` và firewall port 22;
- bật Wake-on-Magic-Packet cho Ethernet adapter;
- gọi `powercfg /deviceenablewake`;
- disable Fast Startup khi có `-DisableFastStartup`;
- tạo Scheduled Task `Wake Kali VM` với `LogonType Interactive`;
- task chạy `vmrun start "<VMX_PATH>" gui`.

Script không tự cấu hình Windows password hoặc auto-logon để password không bị đưa vào command history.

### 6.5 Kiểm tra WoL trong Windows

```powershell
Get-NetAdapter -Name "<ETHERNET_NAME>"
Get-NetAdapterPowerManagement -Name "<ETHERNET_NAME>"
powercfg /devicequery wake_armed
```

Trong Device Manager → Network adapters → Ethernet NIC:

1. Advanced → `Wake on Magic Packet`: Enabled.
2. Nếu có `Shutdown Wake-On-Lan`: Enabled.
3. Power Management → `Allow this device to wake the computer`: checked.
4. `Only allow a magic packet to wake the computer`: checked.

Sau khi shutdown, đèn cổng Ethernet trên PC/router nên vẫn sáng hoặc nhấp nháy. Nếu đèn tắt hoàn toàn, kiểm tra lại BIOS/ErP/NIC driver/Fast Startup.

### 6.6 Cấu hình Windows auto-logon

Dùng [Microsoft Sysinternals Autologon](https://learn.microsoft.com/en-us/sysinternals/downloads/autologon):

1. Download và giải nén Autologon.
2. Chạy `Autologon64.exe` bằng Administrator.
3. Điền `<WINDOWS_USER>`, computer/domain và **password thật**.
4. Chọn **Enable**.
5. Reboot và xác nhận Windows vào thẳng desktop.

Autologon lưu credential dưới dạng LSA secret thay vì để password plaintext trong script. Tuy nhiên admin cục bộ vẫn có thể trích xuất nó và người có quyền truy cập vật lý sẽ vào thẳng desktop; chỉ dùng khi PC ở vị trí được bảo vệ.

### 6.7 Kiểm tra Scheduled Task

Khi Windows đã auto-login và VMware đang đóng:

```powershell
schtasks /run /tn "Wake Kali VM"
Get-ScheduledTask -TaskName "Wake Kali VM"
Get-ScheduledTaskInfo -TaskName "Wake Kali VM"
```

Kết quả đúng: VMware GUI xuất hiện trong desktop session và Kali boot.

Không đổi task sang chạy `SYSTEM` hoặc `Run whether user is logged on or not`: session đó không interactive nên VMware GUI có thể chạy vô hình. Đây là lý do flow sử dụng Windows auto-logon + `LogonType Interactive`.

## 7. Kali VM: auto-login, SSH và TigerVNC

### 7.1 Hoàn thiện Kali clean install

Từ VMware console:

1. Tạo user, ví dụ `kali`.
2. Cài XFCE/LightDM (desktop mặc định của Kali installer là phù hợp).
3. Update hệ thống:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

Kali thường tự cài VMware guest tools khi phát hiện VMware. `pwnbox.sh` vẫn đảm bảo `open-vm-tools` và `open-vm-tools-desktop` có mặt để `vmrun stop ... soft` hoạt động. Tham khảo [Kali VMware Guest Tools](https://www.kali.org/docs/virtualization/install-vmware-guest-tools/).

### 7.2 Cài Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
tailscale ip -4
```

Ghi lại `<KALI_TS_IP>`.

### 7.3 Chạy pwnbox setup

```bash
git clone https://github.com/dzwng/pwnbox-anywhere.git
cd pwnbox-anywhere
chmod +x pwnbox.sh
sudo ./pwnbox.sh install --enable-autologin
```

Script hỏi VNC password 6-8 ký tự. TigerVNC chỉ dùng tối đa 8 ký tự, nên script từ chối password dài hơn thay vì âm thầm cắt bớt.

Những gì được cài/cấu hình:

- đảm bảo `openssh-server` có mặt và enable ở boot; SSH được xem là thành phần nền của Kali, không thuộc phạm vi uninstall của Pwnbox;
- `tigervnc-standalone-server` và XFCE startup;
- `dbus-x11`;
- `open-vm-tools` + `open-vm-tools-desktop`;
- LightDM drop-in `/etc/lightdm/lightdm.conf.d/50-pwnbox-autologin.conf`;
- command `/usr/local/bin/pwnbox`.

tmux không nằm trong danh sách này.

Reboot Kali:

```bash
sudo reboot
```

Xác nhận:

- Kali vào thẳng XFCE mà không hỏi password.
- Tailscale tự kết nối.
- SSH chạy.

```bash
pwnbox status
systemctl status ssh --no-pager
systemctl status open-vm-tools --no-pager
tailscale status
```

### 7.4 TigerVNC on-demand

VNC không chạy 24/7. Khi cần GUI từ xa:

```bash
pwnbox vnc start
pwnbox vnc status
```

VNC chỉ listen trên `127.0.0.1:5901`; Mac phải đi qua SSH tunnel. Khi dùng xong:

```bash
pwnbox vnc stop
```

Đổi resolution hoặc password:

```bash
sudo VNC_RESOLUTION=2560x1440 pwnbox install
sudo pwnbox install --reset-vnc-password
```

### 7.5 tmux là phần riêng của user

Nếu clean Kali chưa có tmux và bạn muốn dùng:

```bash
sudo apt install -y tmux
tmux
```

`pwnbox.sh` không cài, tạo alias, kiểm tra status hoặc uninstall tmux.

## 8. MacBook: SSH key cho Android, Windows và Kali

### 8.1 Tạo ba key riêng

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh

ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_android -C 'mac-to-android'
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_windows -C 'mac-to-windows'
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_kali -C 'mac-to-kali'

chmod 600 ~/.ssh/pwnbox_android ~/.ssh/pwnbox_windows ~/.ssh/pwnbox_kali
chmod 644 ~/.ssh/pwnbox_android.pub ~/.ssh/pwnbox_windows.pub ~/.ssh/pwnbox_kali.pub
```

Có thể đặt passphrase cho key và lưu vào macOS Keychain. Ba key riêng giúp rotate/revoke từng thiết bị mà không ảnh hưởng hai máy còn lại.

### 8.2 Copy key vào Android

```bash
ssh-copy-id \
  -i ~/.ssh/pwnbox_android.pub \
  -p 8022 \
  <TERMUX_USER>@<ANDROID_TS_IP>
```

Nhập Termux password đã tạo ở bootstrap script.

### 8.3 Copy key vào Kali

```bash
ssh-copy-id \
  -i ~/.ssh/pwnbox_kali.pub \
  <KALI_USER>@<KALI_TS_IP>
```

### 8.4 Cài Windows key

Copy public key vào clipboard trên Mac:

```bash
pbcopy < ~/.ssh/pwnbox_windows.pub
```

Trên Windows, mở PowerShell Administrator tại repo và paste key vào biến. Dùng single quote vì public key là dữ liệu, không phải lệnh:

```powershell
$MacPublicKey = 'ssh-ed25519 AAAA... mac-to-windows'

.\setup-windows.ps1 `
    -VmxPath "<VMX_PATH>" `
    -EthernetAdapter "<ETHERNET_NAME>" `
    -WindowsUser "$env:COMPUTERNAME\<WINDOWS_USER>" `
    -MacPublicKey $MacPublicKey `
    -DisableFastStartup
```

Với Windows administrator account, OpenSSH đọc `%ProgramData%\ssh\administrators_authorized_keys`, không đọc file user thông thường. Script đặt key đúng file và sửa ACL chỉ còn Administrators + SYSTEM theo yêu cầu của [Microsoft OpenSSH key management](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement).

### 8.5 Tạo `~/.ssh/config`

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
    Port 22
    IdentityFile ~/.ssh/pwnbox_windows
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3

Host pwnbox-kali
    HostName <KALI_TS_IP>
    User <KALI_USER>
    Port 22
    IdentityFile ~/.ssh/pwnbox_kali
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPersist 10m
    ControlPath ~/.ssh/cm-%C
```

```bash
chmod 600 ~/.ssh/config
```

Test từng hop và kiểm tra host-key fingerprint trước khi accept:

```bash
ssh pwnbox-android 'whoami'
ssh pwnbox-windows 'whoami'
ssh pwnbox-kali 'whoami'
```

Chỉ tiếp tục khi cả ba lệnh không hỏi account password.

### 8.6 Tắt password SSH sau khi key đã test

Đây là bước tùy chọn nhưng nên làm. Luôn giữ một SSH terminal đang mở trong lúc test terminal mới.

Android/Termux:

```bash
ssh pwnbox-android
grep -q '^PasswordAuthentication ' "$PREFIX/etc/ssh/sshd_config" \
  && sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' "$PREFIX/etc/ssh/sshd_config" \
  || printf '\nPasswordAuthentication no\n' >> "$PREFIX/etc/ssh/sshd_config"
pkill -f '[s]shd'
sshd
exit
```

Kali:

```bash
ssh pwnbox-kali
printf 'PasswordAuthentication no\n' | \
  sudo tee /etc/ssh/sshd_config.d/99-pwnbox.conf
sudo sshd -t
sudo systemctl reload ssh
exit
```

Windows PowerShell Administrator:

```powershell
$sshdConfig = "$env:ProgramData\ssh\sshd_config"
$content = Get-Content -LiteralPath $sshdConfig -Raw
if ($content -match '(?m)^\s*PasswordAuthentication\s+') {
    $content = $content -replace '(?m)^\s*PasswordAuthentication\s+.*$', 'PasswordAuthentication no'
} else {
    $content += "`r`nPasswordAuthentication no`r`n"
}
Set-Content -LiteralPath $sshdConfig -Value $content -Encoding ascii
& "$env:WINDIR\System32\OpenSSH\sshd.exe" -t
Restart-Service sshd
```

Mở terminal Mac mới và test lại cả ba host. Nếu key login lỗi, dùng console cục bộ để hoàn tác dòng `PasswordAuthentication no`.

## 9. MacBook: aliases và workflow

### 9.1 Cài function file

Clone repo trên Mac:

```bash
git clone https://github.com/dzwng/pwnbox-anywhere.git ~/Code/pwnbox-anywhere
mkdir -p ~/.config/pwnbox
cp ~/Code/pwnbox-anywhere/macos-pwnbox.zsh.example \
  ~/.config/pwnbox/aliases.zsh
nano ~/.config/pwnbox/aliases.zsh
```

Sửa ba dòng đầu:

```zsh
PWNBOX_PC_MAC='<PC_MAC>'
PWNBOX_VMRUN='C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe'
PWNBOX_VMX='<VMX_PATH>'
```

Thêm cuối `~/.zshrc`:

```zsh
source ~/.config/pwnbox/aliases.zsh
```

Apply:

```bash
source ~/.zshrc
```

### 9.2 Bật từng tầng

```bash
pc_up
# Chờ Windows boot + Autologon hoàn tất.
kali_up
# Chờ Kali boot + Tailscale + sshd.
pwnbox_ssh
```

Hoặc tự động chờ:

```bash
pwnbox_up
pwnbox_ssh
```

`pwnbox_up` thực hiện:

1. Android gửi WoL.
2. Poll Windows SSH tối đa 180 giây.
3. Chờ thêm 20 giây để Autologon tạo interactive desktop.
4. Chạy Scheduled Task `Wake Kali VM`.
5. Poll Kali SSH tối đa 240 giây.

### 9.3 Terminal và tmux

```bash
pwnbox_ssh
tmux
```

Hoặc tự attach session bằng lệnh bạn tự quản lý:

```bash
ssh -t pwnbox-kali 'tmux new-session -A -s main'
```

### 9.4 Browser local port-forward

Nếu tool trên Kali chạy ở `127.0.0.1:8080`:

```bash
ssh -N -L 8080:127.0.0.1:8080 pwnbox-kali
```

Mở [http://127.0.0.1:8080](http://127.0.0.1:8080) trên Mac.

Nhiều port trong một connection:

```bash
ssh -N \
  -L 8080:127.0.0.1:8080 \
  -L 3000:127.0.0.1:3000 \
  -L 8000:127.0.0.1:8000 \
  pwnbox-kali
```

### 9.5 TigerVNC

```bash
pwnbox_vnc
```

Function sẽ:

1. SSH vào Kali chạy `pwnbox vnc start`.
2. Mở tunnel Mac `5901` → Kali `127.0.0.1:5901`.
3. Giữ tunnel ở foreground.

Mở TigerVNC Viewer/RealVNC Viewer và connect `127.0.0.1:5901`. `Ctrl-C` chỉ đóng tunnel; session VNC trên Kali vẫn chạy để reconnect. Tắt hẳn:

```bash
pwnbox_vnc_stop
```

### 9.6 Shutdown đúng thứ tự

Từng bước:

```bash
kali_down
pc_down
```

Hoặc:

```bash
pwnbox_down
```

`kali_down` dùng `vmrun stop ... soft`, cần `open-vm-tools` trong Kali. Chỉ shutdown Windows sau khi lệnh này hoàn tất. Không dùng `vmrun ... hard` trừ trường hợp recovery vì nó tương đương rút điện VM.

## 10. End-to-end acceptance test

Chỉ coi setup hoàn tất sau khi pass đầy đủ checklist này.

### Test A — Android relay

1. Reboot Android.
2. Không mở Termux thủ công.
3. Đợi Tailscale online.
4. Từ Mac: `ssh pwnbox-android 'ps -ef | grep "[s]shd"'`.

### Test B — WoL từ trạng thái Windows shutdown

1. Shutdown Windows hoàn toàn.
2. Xác nhận Android vẫn online.
3. Chạy `pc_up` trên Mac.
4. Xác nhận PC bật và Windows vào thẳng desktop.
5. Xác nhận `ssh pwnbox-windows 'whoami'` hoạt động.

### Test C — Scheduled Task mở VMware GUI

1. Đảm bảo Windows đã auto-login.
2. Chạy `kali_up`.
3. Xác nhận VMware GUI xuất hiện và Kali boot.
4. Xác nhận `ssh pwnbox-kali 'pwnbox status'` hoạt động.

### Test D — Web tunnel và VNC

1. Chạy một HTTP service thử trên Kali.
2. Forward port và mở từ browser Mac.
3. Chạy `pwnbox_vnc`, connect VNC viewer.
4. Chạy `pwnbox_vnc_stop`.

### Test E — Shutdown

1. Chạy `kali_down` và xác nhận VM tắt.
2. Chạy `pc_down` và xác nhận PC tắt.
3. Android và Tailscale relay vẫn online để có thể bắt đầu vòng mới.

## 11. Troubleshooting

### Mac không SSH được Android sau reboot

- Mở Termux:Boot một lần sau khi cài.
- Termux và Termux:Boot phải cùng nguồn/signing key.
- Tắt battery optimization cho Termux, Termux:Boot và Tailscale.
- Bật auto-start/background activity theo ROM.
- Kiểm tra `~/.termux/boot/10-pwnbox-relay` executable.
- Mở Termux và chạy lại `termux-wake-lock; sshd`.

### `wol <PC_MAC>` chạy nhưng PC không bật

- Test WoL khi Android và PC cùng LAN trước khi test qua SSH.
- PC phải dùng Ethernet có dây.
- Kiểm tra BIOS Wake on LAN/PCI-E và disable ErP/deep sleep.
- Kiểm tra Fast Startup đã tắt.
- Kiểm tra NIC LED còn sáng sau shutdown.
- Kiểm tra đúng MAC của Ethernet, không lấy MAC Wi-Fi/Tailscale adapter.
- Tắt Wi-Fi client isolation/AP isolation.
- Cập nhật NIC driver từ hãng.

### Windows SSH không vào được

Trên Windows console:

```powershell
Get-Service sshd
Get-NetFirewallRule -Name OpenSSH-Server-In-TCP
Get-Service Tailscale
```

Windows Hello PIN không phải SSH password. Dùng account password hoặc public key.

### Windows public key bị từ chối

Với administrator account:

```powershell
Get-Content "$env:ProgramData\ssh\administrators_authorized_keys"
icacls "$env:ProgramData\ssh\administrators_authorized_keys"
```

ACL chỉ nên có SYSTEM và Administrators. Chạy lại `setup-windows.ps1 -MacPublicKey ...` để script sửa file/ACL.

### `kali_up` báo success nhưng VMware không xuất hiện

- Xác nhận Windows đã auto-login và `explorer.exe` đang chạy.
- Task principal phải đúng `<WINDOWS_USER>`.
- `LogonType` phải là `Interactive`.
- Kiểm tra `<VMX_PATH>` và `vmrun.exe`.
- Chạy task trực tiếp tại Windows console.

```powershell
Get-ScheduledTaskInfo -TaskName "Wake Kali VM"
schtasks /run /tn "Wake Kali VM"
```

### Kali không shutdown bằng `vmrun ... soft`

```bash
systemctl status open-vm-tools --no-pager
sudo apt install --reinstall open-vm-tools open-vm-tools-desktop
sudo systemctl enable --now open-vm-tools
```

### Kali boot nhưng SSH chưa vào được

Từ VMware console:

```bash
systemctl status ssh --no-pager
systemctl status tailscaled --no-pager
tailscale status
sudo systemctl restart ssh tailscaled
```

### VNC không connect

```bash
pwnbox status
pwnbox vnc restart
ss -ltn | grep 5901
find ~/.config/tigervnc ~/.vnc -name '*:1.log' -type f -print 2>/dev/null
```

Port 5901 trên Kali phải chỉ bind localhost; đừng sửa thành `0.0.0.0`. Kiểm tra tunnel Mac vẫn đang chạy.

## 12. Backup tối thiểu sau khi setup xong

Không backup private key lên repo. Nên lưu an toàn các mục sau:

- Repo này.
- Bản ghi placeholder/inventory nhưng không chứa password.
- Ba private SSH key của Mac trong encrypted backup.
- Tailscale recovery/account access.
- VMware `.vmx` path và VM backup/snapshot phù hợp.
- Windows local account recovery information.
- BIOS WoL/virtualization screenshots.

Sau mỗi lần đổi NIC, mainboard, Windows user, Android hoặc Kali VM, cập nhật inventory và SSH config/alias tương ứng.

## 13. Gỡ pwnbox khỏi Kali

```bash
sudo pwnbox uninstall vnc
sudo pwnbox uninstall autologin
sudo pwnbox uninstall all
```

Quy tắc uninstall:

- Không bao giờ stop, disable hoặc purge SSH.
- Không gỡ VMware Tools, XFCE, LightDM, `dbus-x11` hay các package nền dùng chung.
- `uninstall vnc` luôn xóa VNC session/config do Pwnbox tạo.
- Package `tigervnc-standalone-server` chỉ bị purge nếu file quản lý ghi nhận chính Pwnbox là bên đã cài package đó. Nếu TigerVNC đã có từ trước, package được giữ nguyên.
- `uninstall autologin` chỉ xóa drop-in `/etc/lightdm/lightdm.conf.d/50-pwnbox-autologin.conf` do Pwnbox tạo.
- `uninstall all` tương đương gỡ VNC artifact + autologin drop-in + command `/usr/local/bin/pwnbox`; SSH vẫn hoạt động.

## License

MIT
