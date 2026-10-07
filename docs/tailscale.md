# Phase 2: Tailscale trực tiếp trên Windows và Kali

Mac, ThinkPad, Windows và Kali dùng cùng tailnet. Windows/Kali là hai node riêng;
chỉ node của OS đang chạy online. Mac kết nối trực tiếp tới node desktop để dùng
SSH/RDP/VNC tunnel; ThinkPad nhận command control và dùng LAN/WoL như Phase 1.

## Windows

Giữ client Tailscale đã cài/đăng nhập nếu node Windows đang hoạt động.
Nếu chưa có, cài từ [Tailscale Windows](https://tailscale.com/download/windows)
và đăng nhập cùng tailnet. Ghi lại tên node và `tailscale ip -4`.

Windows OpenSSH phải nhận được traffic tailnet. Chạy setup bằng PowerShell admin:
Thay `192.0.2.0/24` bên dưới bằng subnet LAN thực tế; đây chỉ là dải IP mẫu.

```powershell
.\setup-windows.ps1 -PublicKeyFile C:\path\thinkpad-windows.pub `
    -AllowedRemoteAddress @('192.0.2.0/24', '100.64.0.0/10')
```

Có thể thay dải tailnet bằng IP Tailscale Mac cụ thể. Access rules tailnet phải cho
Mac tới Windows:22; thêm 3389 nếu dùng RDP. RDP cần bật riêng trên Windows và có rule
firewall giới hạn tailnet. Không mở port public.

## Kali bare-metal

Cài Tailscale từ [hướng dẫn Linux chính thức](https://tailscale.com/docs/install/linux).
Nếu chưa có client, tải script installer vào file rồi chạy:

```bash
curl -fsSL https://tailscale.com/install.sh -o /tmp/pwnbox-tailscale-install.sh
sudo sh /tmp/pwnbox-tailscale-install.sh
sudo systemctl enable --now tailscaled
sudo tailscale up --hostname=pwnbox-kali
tailscale ip -4
tailscale status
```

Nếu đã đăng nhập, giữ identity hiện có; có thể đổi tên node bằng
`sudo tailscale set --hostname=pwnbox-kali`. Dùng trình duyệt thường để mở link
đăng nhập CLI cung cấp. Không dùng auth key/private state của node VMware cũ;
node bare-metal có identity riêng. Giữ OpenSSH đã setup, key Mac interactive riêng.

Firewall Kali cần cho SSH tới interface Tailscale (nếu firewall đang chặn).
Dùng OpenSSH hiện tại; không cần bật tính năng Tailscale SSH. VNC vẫn localhost,
truy cập bằng SSH tunnel.

## Mac và kiểm tra

Merge [SSH config](../config/ssh-macos.conf.example). HostName mỗi OS là tên
MagicDNS thực tế hoặc IP `100.x` của node đó; giữ HostKeyAlias riêng.
MagicDNS phải bật nếu dùng tên: [MagicDNS](https://tailscale.com/docs/features/magicdns).

```zsh
ssh pwnbox-relay '/usr/local/bin/pwnbox status'
ssh -G kali
ssh kali
ssh windows
tailscale ping pwnbox-kali
```

Thử từng OS khi nó đang chạy. `ssh -G kali` phải trỏ tới node Kali và không có
ProxyJump. Kiểm tra status/ping để biết kết nối direct hay relay; direct thường có
performance tốt hơn: [connection types](https://tailscale.com/docs/reference/connection-types).
Test SSH/SCP và RDP/VNC từ hotspot/mạng ngoài nhà sau khi setup.

## Controller vẫn dùng LAN

Không đổi WINDOWS_HOST/KALI_HOST trên ThinkPad sang IP Tailscale trong bước này.
Phase 1 đã kiểm thử SSH automation/WoL qua LAN; DHCP reservation hoặc hostname LAN
ổn định vẫn cần cho controller. IP Tailscale Windows/Kali là endpoint tương tác riêng
của Mac và không phụ thuộc DHCP LAN. Không cần cấu hình gateway/route trên ThinkPad.
