# Dual boot, firmware và WoL

Project dùng dual boot đã cài và hoạt động, với Windows là OS mặc định.
Windows và Kali có EFI loader/entry sẵn; setup không thay partition, GRUB hay BootOrder.

Xác định UEFI boot ID của Windows/Kali và BCD firmware GUID của Kali trên máy bạn.
Điền vào config riêng; ID, GUID và đường dẫn disk phụ thuộc từng máy.

## Read-only checks trước thử nghiệm

Kali: `sudo efibootmgr -v`, `findmnt /boot/efi`, `lsblk -f`, `sudo ethtool YOUR_ETHERNET_INTERFACE`.
Windows elevated PowerShell: `bcdedit /enum firmware`, kiểm tra BitLocker và có recovery key.
Xác minh ID trỏ tới đúng loader; không suy ra Windows BCD GUID từ số UEFI boot ID.

## Chuyển OS một lần

Windows -> Kali (thay placeholder bằng GUID đã xác minh):

```powershell
bcdedit /set '{fwbootmgr}' bootsequence '{KALI_FIRMWARE_GUID}'
# Chỉ chạy reboot nếu bcdedit thành công.
shutdown /r /t 0
```

Kali -> Windows (thay placeholder bằng UEFI ID Windows đã xác minh):

```bash
sudo efibootmgr -n WINDOWS_BOOT_ID
sudo reboot
```

Controller dùng hai cơ chế này. Helper Kali lấy ID từ `/etc/pwnbox/windows-boot-id`,
chỉ root sửa được. `KALI_BOOT_ID` trong controller config mô tả mapping, không dùng
để tạo entry. `WINDOWS_BOOT_ID` phải khớp giá trị truyền cho setup Kali.
[efibootmgr manual](https://manpages.debian.org/trixie/efibootmgr/efibootmgr.8.en.html).

## WoL

Điền MAC Ethernet desktop vào config, xác định tên interface trên Kali và kiểm tra
`Wake-on: g`. V2 không tự đổi NIC đang chạy.
Magic packet phải đến đúng broadcast domain; WoL không chọn OS. Boot mặc định là Windows.

Windows setup hỗ trợ `-DisableFastStartup`, `-EnableWakeOnLan -EthernetAdapter Ethernet`.
WoL BIOS/NIC và nguồn NIC khi S5 vẫn cần kiểm tra. Sau shutdown từ Kali, thử wake lần nữa.

Nếu Kali làm mất `Wake-on: g` sau reboot, xác định NetworkManager hay systemd-networkd
đang quản lý interface. Với NetworkManager, kiểm tra connection Ethernet rồi sửa đúng
profile (thay tên thực tế):

```bash
nmcli -f NAME,DEVICE connection show --active
sudo nmcli connection modify 'Ethernet profile name' 802-3-ethernet.wake-on-lan magic
# Apply trong lần reboot local tiếp theo; không hạ interface qua remote session.
```

## Acceptance matrix (LAN, có console tại nhà)

Chạy từng trường hợp, ghi lại kết quả. Dừng khi một bước lỗi:

| Ban đầu | Lệnh | Mong đợi |
|---|---|---|
| OFF | `pwnbox windows` | WoL -> Windows; endpoint nhận diện đúng |
| OFF | `pwnbox kali` | WoL -> Windows -> BootNext -> Kali |
| Windows | `pwnbox kali` | Một lần reboot sang Kali |
| Kali | `pwnbox windows` | Một lần reboot sang Windows |
| Windows | `pwnbox off` | Clean shutdown; OFF được suy luận |
| Kali | `pwnbox off` | Clean shutdown; WoL lần sau vẫn hoạt động |
| Windows/Kali | Lệnh chọn chính OS đó | Không WoL/reboot |

Sau mỗi vòng, kiểm tra BootOrder giữ nguyên. Windows Update hoặc firmware
ngoài project có thể thay đổi môi trường; xem console nếu timeout. Không tự sửa BootOrder.

## Hardware test tự động trên ThinkPad

Sau khi cả hai automation key và host identity đã cài, desktop đang Windows và đã
lưu công việc, có thể chạy `bash tests/test-lan.sh --run` trên ThinkPad. Đây là test
máy thật: reboot, shutdown và WoL nhiều lần; thành công sẽ kết thúc ở Windows.
Script dừng ở lỗi đầu tiên, không tự retry reboot hoặc ép tắt nguồn. Không dùng nó
để cài Kali endpoint lần đầu. Log/result mặc định ở `~/.local/state/pwnbox/hardware-*`.

Nếu Codex đang chạy trên desktop Windows, khởi chạy test trên relay bằng nohup để
tiến trình sống qua reboot. `PWNBOX_TEST_RUN_DIR` chọn thư mục log; tạo file `cancel`
trong đó để dừng trước bước tiếp theo. Việc quay lại Windows không tự mở ứng dụng.
