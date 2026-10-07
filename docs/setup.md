# Cài đặt Pwnbox Anywhere v2

Runbook cài đặt lần đầu. Nếu hệ thống đã setup, xem [README và cheatsheet](../README.md)
để dùng hằng ngày. Chạy từng bước trên đúng máy, từ thư mục repository.

IP trong dải `192.0.2.0/24`, MAC, username và GUID ở đây chỉ là giá trị mẫu.
Thay bằng thông tin của máy bạn trước khi chạy. Dải IP mẫu dành cho tài liệu theo
[RFC 5737](https://www.rfc-editor.org/rfc/rfc5737), không dùng để cấu hình LAN thật.

## Phase 1: setup LAN

Thực hiện khi có console tại nhà; không chạy các lệnh đổi OS trên máy đang làm việc
trước khi key, firmware mapping và quyền remote đã được kiểm tra.

### 1. ThinkPad

Clone/copy repo tới Debian rồi chạy từ user dùng để điều phối:

```bash
sudo bash setup/setup-thinkpad.sh
```

Script cài dependency + CLI, giữ config hiện có. Không tự sửa firewall, power, key hay
Tailscale. Kiểm tra power/gập nắp theo [runbook ThinkPad](../debian-relay.md).

Tạo **hai automation key** và cài public key đúng OS theo [SSH setup](ssh.md).
Private key chỉ ở ThinkPad. Xác minh fingerprint từng OS tại console.

Sửa `~/.config/pwnbox/pwnbox.conf`, dùng `KEY=value` literal không quote/expansion:

```ini
DESKTOP_MAC=02:00:00:00:00:20
WINDOWS_HOST=192.0.2.20
KALI_HOST=192.0.2.20
WINDOWS_USER=your_windows_user
KALI_USER=your_kali_user
WINDOWS_BOOT_ID=0000
KALI_BOOT_ID=0002
KALI_WINDOWS_BCD_GUID={00000000-0000-0000-0000-000000000000}
WOL_BROADCAST=192.0.2.255
LAN_HEALTH_HOST=192.0.2.1
```

Đây là config minh họa; mọi giá trị cần xác nhận trên máy thực tế. Không
copy config riêng vào Git. File mẫu đầy đủ: [pwnbox.conf.example](../config/pwnbox.conf.example).
Tên hai key mặc định: `~/.ssh/pwnbox_control_windows`, `~/.ssh/pwnbox_control_kali`.
Host fingerprints: `~/.ssh/pwnbox_control_known_hosts`. `chmod 600` các file riêng.

### 2. Windows

PowerShell **Run as administrator**, cài public key Windows của ThinkPad:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup-windows.ps1 -PublicKeyFile C:\path\thinkpad-windows.pub `
    -AllowedRemoteAddress @('192.0.2.0/24', '100.64.0.0/10') -DisableFastStartup
```

OpenSSH có startup Automatic; firewall rule cho LAN và tailnet; giữ các key khác.
Không cần VMX, VMware task hoặc Windows autologon. WoL đã hoạt động thì không cần
đổi NIC. Nếu cần, thêm `-EnableWakeOnLan -EthernetAdapter Ethernet`; không restart NIC.
Kiểm tra read-only: `.\setup-windows.ps1 -CheckOnly` (elevated để đọc firmware đầy đủ).

ThinkPad phải SSH key thành công và chạy được `bcdedit /enum firmware` với quyền admin.
Desktop cần IP ổn định/DHCP reservation. Kiểm tra BitLocker/recovery trước vòng thử boot.

### 3. Kali

Copy public key Kali của ThinkPad lên Kali rồi chạy:

```bash
sudo bash setup/setup-kali.sh --user your_kali_user --windows-boot-id 0000 \
  --automation-public-key /path/thinkpad-kali.pub
```

Script cài SSH, efibootmgr, endpoint forced command và sudoers cho reboot/shutdown.
Không đổi BootNext trong setup; không đụng partitions/GRUB/BootOrder. Kali user phải
đúng user đã cài. Kiểm tra WoL persistence trên `eth0` theo [dualboot.md](dualboot.md).

### 4. Test controller

Khi mỗi OS đang chạy, test automation SSH và fingerprint theo [docs/ssh.md](ssh.md).
Sau đó:

```bash
pwnbox doctor
pwnbox status
pwnbox kali
pwnbox kali       # đã Kali: không reboot lại
pwnbox windows
pwnbox off
pwnbox wake
```

Test đủ [acceptance matrix](dualboot.md), gồm OFF -> Kali và shutdown từ cả hai OS.
CLI có timeout/retries hữu hạn; exit codes ở [troubleshooting](troubleshooting.md).

## Phase 2: Tailscale trực tiếp trên từng OS

Cài/đăng nhập Tailscale trên Windows và Kali bằng cùng tailnet với Mac/ThinkPad.
Giữ hai OS thành hai node riêng, dùng tên MagicDNS hoặc IP Tailscale riêng cho Mac.
Theo [docs/tailscale.md](tailscale.md). ThinkPad tiếp tục WoL/SSH automation qua
LAN; không cần thay controller đã kiểm thử. Chỉ tiếp tục khi Phase 1 đã pass.

## Phase 3: MacBook

Giữ/tạo key interactive riêng, merge [SSH config mẫu](../config/ssh-macos.conf.example).
Alias `kali` trỏ tới **tên hoặc IP Tailscale của Kali**, không có ProxyJump.
Alias Windows dùng node Tailscale của Windows; alias relay dùng node ThinkPad.

```bash
mkdir -p ~/.config/pwnbox
cp macos-pwnbox.zsh.example ~/.config/pwnbox/aliases.zsh
# Thêm một lần vào ~/.zshrc: source ~/.config/pwnbox/aliases.zsh
source ~/.config/pwnbox/aliases.zsh
pwnbox kali
ssh kali
```

`pwnbox` trên Mac delegate control tới `/usr/local/bin/pwnbox` trên ThinkPad.
`pwnbox ssh` kết nối trực tiếp tới Kali. Khác key ThinkPad automation.
