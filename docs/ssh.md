# SSH: automation và interactive

## 1. Key trên ThinkPad

Chạy bằng user Debian dùng để điều phối. Không ghi đè key đã có:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_control_windows -C 'thinkpad-control-windows'
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_control_kali -C 'thinkpad-control-kali'
touch ~/.ssh/pwnbox_control_known_hosts
chmod 600 ~/.ssh/pwnbox_control_known_hosts
```

Unattended controller cần key không có passphrase hoặc agent đang giữ key. CLI dùng
BatchMode và không hỏi password. Private key chỉ ở ThinkPad, không copy vào repository.
Chỉ chuyển file `.pub` để cài trên Windows/Kali.

Windows: chạy root `setup-windows.ps1` với public key Windows trên máy Windows, bằng
account administrator sẽ dùng cho SSH. Script giữ key khác, dùng ACL SYSTEM/Administrators
và Match User. Account admin automation có quyền rộng; không dùng key này trên Mac.
[Microsoft OpenSSH configuration](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration).

Kali: `sudo bash setup/setup-kali.sh --user your_kali_user --windows-boot-id 0000 --automation-public-key /path/thinkpad-kali.pub`.
Public key bị forced command `pwnbox-kali-control` và `restrict`; không mở shell,
SFTP hay forwarding bằng key này. Endpoint chỉ nhận status/windows/off. Sudoers cho
đúng hai action, không cấp sudo shell hay `efibootmgr *`.

## 2. Host fingerprint (quan trọng khi cùng IP)

Tại console Windows:

```powershell
ssh-keygen -lf "$env:ProgramData\ssh\ssh_host_ed25519_key.pub"
```

Tại console Kali:

```bash
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Khi mỗi OS đang chạy, dùng ThinkPad kết nối **một lần** với HostKeyAlias riêng.
Thay user/IP theo config, so sánh fingerprint với console rồi mới chấp nhận:

```bash
ssh -F /dev/null -o HostKeyAlias=pwnbox-control-windows \
  -o UserKnownHostsFile=~/.ssh/pwnbox_control_known_hosts -o IdentitiesOnly=yes \
  -i ~/.ssh/pwnbox_control_windows WINDOWS_USER@WINDOWS_LAN_IP \
  'powershell.exe -NoProfile -Command "[Environment]::OSVersion.Platform; bcdedit /enum firmware"'

ssh -F /dev/null -o HostKeyAlias=pwnbox-control-kali \
  -o UserKnownHostsFile=~/.ssh/pwnbox_control_known_hosts -o IdentitiesOnly=yes \
  -i ~/.ssh/pwnbox_control_kali KALI_USER@KALI_LAN_IP status
```

Thêm `-p PORT` nếu không dùng 22. CLI sau đó bắt buộc StrictHostKeyChecking=yes.
Không tắt host-key checking hoặc chấp nhận fingerprint chỉ vì ssh-keyscan trả về.

## 3. Mac interactive key

Giữ key riêng `~/.ssh/pwnbox_relay`, `~/.ssh/pwnbox_kali`, `~/.ssh/pwnbox_windows`.
Nếu đã có, tái sử dụng; không tạo ghi đè. Cài Kali interactive `.pub` như key SSH thông
thường, không forced command. Tại console Kali, bằng user sẽ SSH (không sudo):

```bash
bash setup/setup-kali-interactive.sh /path/mac-pwnbox_kali.pub
```

Copy/merge `config/ssh-macos.conf.example` vào SSH config.
Fingerprint interactive alias được xác minh giống bước trên.

```bash
ssh pwnbox-relay hostname
ssh kali
ssh -N -L 127.0.0.1:8080:127.0.0.1:8080 kali
```

Alias interactive trên Mac dùng tên/IP Tailscale riêng của mỗi OS. Cài và đăng nhập
Tailscale trên Windows/Kali theo [network setup](tailscale.md). ThinkPad automation
vẫn dùng LAN. Không thêm ProxyJump. Không expose SSH/RDP/VNC public.

## 4. Harden sau khi test key

Giữ console hoặc session đang mở. Debian/Kali: kiểm tra drop-in SSH và kết quả
`sudo sshd -T`, sau đó tắt password authentication; validate bằng `sudo sshd -t`
trước reload. Windows kiểm tra `sshd.exe -t` trước restart. Không tự tắt password trong
setup lần đầu để tránh khóa truy cập trước khi key đã được chứng minh hoạt động.
