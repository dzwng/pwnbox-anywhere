# ThinkPad Debian: controller 24/7

ThinkPad làm WoL relay và OS orchestrator.
Mac chạy command control qua SSH tới relay; interactive SSH tới desktop là direct
Tailscale connection tới OS đang chạy. Các ví dụ dùng SSH alias `pwnbox-relay`;
điền hostname và user Debian của bạn trong SSH config.

## Install và kiểm tra

```bash
sudo bash setup/setup-thinkpad.sh
systemctl is-enabled ssh
systemctl is-active ssh
ip -4 addr
ip route
```

Setup không tự sửa nguồn điện, firewall hoặc Tailscale. Điền config và cài automation
key theo [README](README.md) và [SSH runbook](docs/ssh.md). Không chạy CLI bằng sudo;
controller user sở hữu key, config, state và operation lock.

## Giữ máy online sau gập nắp/reboot

Kiểm tra các cấu hình đã chọn từ setup cũ:

```bash
systemctl status sleep.target suspend.target hibernate.target hybrid-sleep.target
sudo tlp-stat -s
sudo tlp-stat -b
```

Nếu chưa cấu hình, thực hiện ở console (restart logind có thể ảnh hưởng session):

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

`/etc/systemd/logind.conf` hoặc drop-in riêng:

```ini
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

XFCE Power Manager: lid action Do nothing trên AC và battery. TLP charge threshold
40–70% là lựa chọn trước đây, kiểm tra hardware hỗ trợ và giá trị thực tế bằng tlp-stat.
Giữ máy thoáng, nguồn ổn định, test SSH sau reboot và gập nắp 5 phút. Wi-Fi phải giữ
kết nối; Ethernet tốt hơn cho relay ổn định. Không tự đổi các thiết lập này trong installer.

## SSH và firewall theo phase

Phase 1 phải giữ đường truy cập LAN để setup/test. Cài key Mac -> relay, xác minh
fingerprint tại console. Sau key test mới tắt password authentication, kiểm tra
`sudo sshd -t` và effective `sudo sshd -T`, rồi reload SSH và thử session mới.

Phase 2 dùng Tailscale trực tiếp trên Windows và Kali. Relay chỉ cần nhận SSH control
từ Mac qua Tailscale và dùng LAN tới desktop; không cần rule FORWARD cho flow này.
Xem [Tailscale setup](docs/tailscale.md).
Không bật UFW deny LAN trong lúc setup nếu chỉ còn kết nối qua LAN.

## WoL

Relay phải cùng broadcast domain với desktop. Dùng config DESKTOP_MAC/WOL_BROADCAST;
controller phát magic packet bằng Python, không cần root. Có thể kiểm tra độc lập:

```bash
sudo apt install wakeonlan
wakeonlan -i LAN_BROADCAST DESKTOP_ETHERNET_MAC
```

WoL không chọn OS. Sau power-on Windows boot mặc định; `pwnbox kali` chờ Windows
control endpoint rồi đặt one-time boot Kali. Kiểm tra WoL từ trạng thái shutdown của
cả hai OS, theo [dualboot runbook](docs/dualboot.md).

## Locale từ Mac

Nếu `LC_CTYPE=UTF-8` gây warning, SSH có thể vẫn thành công. Kiểm tra `locale -a` và
các dòng AcceptEnv trong sshd_config/drop-ins. Bỏ LANG/LC_* khỏi AcceptEnv nếu muốn
Debian dùng locale riêng; các dòng AcceptEnv có thể cộng dồn. Validate sshd trước reload.
Không coi warning locale là lỗi kết nối Tailscale hoặc lỗi key.
