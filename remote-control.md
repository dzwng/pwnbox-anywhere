# Remote control v2

Setup LAN trước, theo [README](README.md). Remote direct access cần hoàn tất
[Tailscale trên từng OS](docs/tailscale.md). Trên Mac đã source aliases:

```bash
pwnbox status
pwnbox kali
ssh kali
pwnbox windows
pwnbox off
```

Các command control SSH tới ThinkPad. `ssh kali` và `pwnbox ssh` SSH từ Mac trực tiếp
đến tên/IP Tailscale Kali bằng interactive key; không ProxyJump. Windows SSH
dùng tên/IP Tailscale Windows; GUI Windows dùng AnyDesk hiện có. ThinkPad chỉ xử lý
control, không chuyển tiếp các phiên SSH/VNC/SOCKS này.

```bash
pwnbox_vnc       # localhost:5901, cần helper pwnbox-kali trên Kali
pwnbox_vnc_disconnect # đóng tunnel nền, giữ phiên desktop
pwnbox_vnc_stop  # kết thúc phiên desktop và đóng tunnel
proxy_up        # SOCKS5 localhost:1080; bật remote DNS trong browser
proxy_down
kali_pull '~/htb/loot.zip'
kali_push ./exploit.py '~/htb/'
ssh -N -L 127.0.0.1:8080:127.0.0.1:8080 kali
```

ThinkPad vẫn online sau `pwnbox off`. WoL chỉ bật máy; bootsequence chọn OS một lần.
TigerVNC và Firefox Mac qua SOCKS5: [hướng dẫn GUI/browser](docs/gui-and-browser.md).
Lỗi UNKNOWN/timeout: xem [troubleshooting](docs/troubleshooting.md), không reboot mù.
Flow VMware cũ được lưu ở [legacy](docs/legacy.md).
