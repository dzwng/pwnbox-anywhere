# Debian 13 relay trên ThinkPad X1 Carbon

ThinkPad X1 Carbon Gen 8 (i5-10210U, RAM 8 GB, SSD 256 GB) thay Android/Termux làm WoL relay 24/7. Debian nhận lệnh SSH qua Tailscale rồi phát magic packet tới card Ethernet của Windows trong LAN. Không cần subnet router, exit node hay mở port router cho flow này.

Context đã ghi nhận: Debian 13 XFCE, hostname `debian`, user `zwng`, sleep targets đã mask, lid đã đặt ignore/Do nothing, TLP charge threshold 40–70%, OpenSSH đã cài. Lần test sau đã SSH từ Mac vào `pwnbox-relay` qua Tailscale/MagicDNS thành công bằng password, còn cảnh báo locale. Các bước hardening và test WoL dưới đây là checklist cần xác nhận trên máy thật, không phải khẳng định đã hoàn thành.

## 1. Kiểm tra base system và reboot

Trên Debian:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y openssh-server wakeonlan
sudo systemctl enable --now ssh
systemctl is-enabled ssh
systemctl is-active ssh
systemctl status sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo tlp-stat -s
sudo tlp-stat -b
```

SSH phải `enabled` / `active`; bốn sleep target phải `masked`. Cấu hình power đã chọn:

```ini
# /etc/systemd/logind.conf
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

```ini
# /etc/tlp.conf (hoặc drop-in TLP đang dùng)
START_CHARGE_THRESH_BAT0=40
STOP_CHARGE_THRESH_BAT0=70
```

Trong XFCE **Settings → Power Manager → System**, đặt lid action thành **Do nothing** cho cả AC và battery. Kiểm tra các giá trị TLP thực tế bằng `tlp-stat -b`; không chỉ dựa vào nội dung file.

Nếu chưa reboot sau thay đổi logind/power:

```bash
sudo reboot
```

Sau reboot, gập nắp khoảng 5 phút rồi SSH từ máy khác. Trước khi khóa SSH chỉ qua Tailscale, có thể test trong LAN bằng `ssh zwng@<RELAY_LAN_IP>`. Đặt máy nơi thoáng, giữ kết nối LAN ổn định; nếu dùng Wi-Fi, xác nhận vẫn kết nối khi gập nắp.

## 2. Tailscale và MagicDNS

Nếu chưa cài/đăng nhập, trên Debian:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Mở URL đăng nhập bằng account của tailnet đang dùng cho Mac/Windows/Kali. Trong Admin Console → Machines, đặt tên máy là `pwnbox-relay`; Linux hostname vẫn giữ `debian`.

```bash
tailscale status
tailscale ip -4
systemctl is-active tailscaled
```

Trên Mac đã kết nối cùng tailnet:

```bash
tailscale ping pwnbox-relay
ssh zwng@pwnbox-relay
```

Nếu MagicDNS chưa resolve, dùng IP từ `tailscale ip -4` và kiểm tra MagicDNS trong Admin Console. Linux chạy Tailscale bằng daemon `tailscaled`, không cần đăng nhập desktop để online. Windows cần bật **Preferences → Run unattended** trong menu tray Tailscale; chế độ này giúp Tailscale online sau reboot/sign-out, còn VMware GUI vẫn cần Windows Autologon theo README. [Tailscale: unattended mode](https://tailscale.com/docs/how-to/run-unattended).

## 3. Device key expiry

Đây là thời hạn key của thiết bị đã tham gia tailnet, khác với auth key dùng để enroll máy. Tailnet mới mặc định có thời hạn 180 ngày; thời hạn thực tế phụ thuộc cấu hình tailnet. Khi key hết hạn, kết nối tới/từ máy dừng cho tới khi re-authenticate. [Tailscale: key expiry](https://tailscale.com/docs/features/access-control/key-expiry).

Khuyến nghị cho topology này:

| Thiết bị | Key expiry | Lý do |
|---|---|---|
| Debian relay | Tắt | Relay 24/7, cần bật PC từ xa |
| Windows host | Tắt | Cần truy cập được sau WoL/reboot |
| Kali VM cố định | Có thể tắt | Dùng như remote pwnbox; cân nhắc lại nếu VM thường xuyên recreate |
| MacBook / iPhone | Giữ bật | Thiết bị cá nhân, dễ re-authenticate |

Admin Console → **Machines → menu … của từng máy → Disable key expiry**. Đây là khuyến nghị, không tự động thay đổi bởi repo. Với máy đã tắt expiry, chủ động revoke/remove device nếu mất máy hoặc lộ credentials.

## 4. SSH key riêng cho relay

Trên Mac, tạo key nếu chưa có (không ghi đè key đang dùng):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_relay -C 'mac-to-pwnbox-relay'
cat ~/.ssh/pwnbox_relay.pub | ssh zwng@pwnbox-relay \
  'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
```

Thêm vào `~/.ssh/config`:

```sshconfig
Host pwnbox-relay
    HostName pwnbox-relay
    User zwng
    IdentityFile ~/.ssh/pwnbox_relay
    IdentitiesOnly yes
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Nếu cần, thay `HostName` bằng IP Tailscale của Debian. Sau đó:

```bash
chmod 600 ~/.ssh/config
ssh -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no pwnbox-relay whoami
```

Kết quả phải là `zwng`, không cần account password. Private key có passphrase vẫn có thể hỏi passphrase hoặc dùng SSH agent. Chỉ harden sau khi test key thành công.

## 5. Harden SSH sau khi key hoạt động

Giữ một session SSH đang mở; trên Debian:

```bash
sudo tee /etc/ssh/sshd_config.d/00-pwnbox-relay.conf >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF
sudo /usr/sbin/sshd -t
sudo /usr/sbin/sshd -T | grep -E '^(permitrootlogin|passwordauthentication|kbdinteractiveauthentication|pubkeyauthentication) '
```

Mong đợi: `permitrootlogin no`, `passwordauthentication no`, `kbdinteractiveauthentication no`, `pubkeyauthentication yes`. OpenSSH thường lấy giá trị gặp đầu tiên; Debian include drop-in ở đầu config, nên đặt tên `00-...` và kiểm tra kết quả thực tế. Nếu đã có file ưu tiên trước hoặc `Match` riêng cho user/địa chỉ, kiểm tra và sửa cấu hình đó; không coi `sshd -t` là bằng chứng password đã bị tắt. [Debian: sshd_config](https://manpages.debian.org/trixie/openssh-server/sshd_config.5.en.html).

Nếu syntax hợp lệ và các giá trị đúng:

```bash
sudo systemctl reload ssh
```

Mở terminal Mac thứ hai, chạy lại lệnh test key ở bước 4. Chỉ đóng session cũ khi phiên mới login thành công.

## 6. Chỉ nhận SSH qua Tailscale

Làm sau khi đã test SSH qua Tailscale bằng key, khi có thể truy cập console Debian để khôi phục nếu cần. Trên Debian:

```bash
sudo apt install -y ufw
sudo ufw status numbered
sudo ufw allow in on tailscale0
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
sudo ufw status verbose
```

Nếu đã có rule mở `22/tcp` hoặc profile `OpenSSH` trên mọi interface, xóa các rule đó theo số trong `ufw status numbered` (xóa số lớn trước rồi kiểm tra lại). Default deny không vô hiệu hóa rule allow cũ. Mô hình này theo [hướng dẫn UFW của Tailscale](https://tailscale.com/docs/how-to/secure-ubuntu-server-with-ufw).

Test phiên SSH **mới** từ Mac:

```bash
ssh -o ConnectTimeout=5 pwnbox-relay whoami
ssh -o ConnectTimeout=5 zwng@<RELAY_LAN_IP>
```

Tailscale phải vào được; kết nối mới bằng IP LAN phải thất bại. `allow in on tailscale0` cho phép traffic tailnet nói chung; Tailscale còn quản lý netfilter riêng, nên giới hạn peer/port trong tailnet bằng policy ACL/grants nếu cần. WoL vẫn gửi ra LAN vì outgoing được phép. Nếu bị khóa, vào console Debian chạy `sudo ufw disable` rồi kiểm tra lại rule.

## 7. WoL và chuyển alias trên Mac

PC Windows phải nối Ethernet, bật WoL trong BIOS/NIC, tắt Fast Startup/ErP theo README. Relay và PC phải cùng broadcast domain; Wi-Fi relay có thể dùng nếu AP không chặn broadcast/isolate client.

Trên Debian, với PC đã shutdown:

```bash
wakeonlan <PC_MAC>
```

Thay placeholder bằng MAC card **Ethernet**. Nếu PC không bật:

```bash
ip -4 addr
wakeonlan -i <LAN_BROADCAST> <PC_MAC>
```

Lấy broadcast ở interface LAN đang nối tới PC, không phải `tailscale0`. Ví dụ `inet 192.168.1.20/24 brd 192.168.1.255` thì dùng `192.168.1.255`. Không cần `sudo` cho `wakeonlan`. [Debian: wakeonlan](https://manpages.debian.org/trixie/wakeonlan/wakeonlan.1.en.html).

Trên Mac, thêm host/key ở bước 4 rồi cập nhật bản `~/.config/pwnbox/aliases.zsh` theo [file mẫu](./macos-pwnbox.zsh.example). Giữ MAC và đường dẫn VMware/VMX thực tế; biến mới `PWNBOX_WOL_BROADCAST` để trống, hoặc đặt broadcast LAN vừa test nếu cần. `git pull` chỉ cập nhật repo, không cập nhật bản alias đã copy.

```bash
source ~/.config/pwnbox/aliases.zsh
ssh pwnbox-relay hostname                    # debian
ssh pwnbox-relay 'wakeonlan <PC_MAC>'         # thêm -i nếu cần
pc_up
pwnbox_up
pwnbox_ssh
```

Test từng lần với PC ở trạng thái tắt để xác nhận WoL; `pwnbox_up` tiếp tục chờ Windows SSH, chạy Scheduled Task rồi chờ Kali SSH. Chỉ ngừng dùng/gỡ relay Android sau khi flow mới hoạt động. `pwnbox_down` tắt Kali và Windows, giữ Debian relay online.

## 8. Cảnh báo locale khi SSH từ Mac

```text
-bash: warning: setlocale: LC_CTYPE: cannot change locale (UTF-8): No such file or directory
```

SSH đã thành công; Mac gửi `LC_CTYPE=UTF-8` nhưng Debian không có locale tên `UTF-8`. Kiểm tra trên Debian bằng `locale` và `locale -a`.

Với relay này, để Debian dùng locale của chính nó: tìm các dòng nhận environment trên Debian:

```bash
sudo grep -Rns '^[[:space:]]*AcceptEnv' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
```

Dùng `sudo nano` mở các file tìm được, bỏ `LANG` và `LC_*` khỏi các dòng `AcceptEnv` (nếu dòng chỉ còn hai giá trị đó thì comment cả dòng). Giữ các biến khác nếu vẫn muốn nhận. Kiểm tra cả drop-in/khối `Match` liên quan; nhiều dòng `AcceptEnv` có thể cộng dồn nên không chỉ thêm một drop-in để mong ghi đè.

```bash
sudo /usr/sbin/sshd -t
sudo systemctl reload ssh
```

Thoát rồi SSH lại. Nếu warning vẫn còn, kiểm tra locale trong shell profile và `/etc/default/locale` trên Debian. Có thể xác nhận nguyên nhân nhanh từ Mac bằng `LC_CTYPE=en_US.UTF-8 ssh pwnbox-relay` nếu `locale -a` trên Debian có `en_US.utf8`. [Debian: AcceptEnv](https://manpages.debian.org/trixie/openssh-server/sshd_config.5.en.html#AcceptEnv).
