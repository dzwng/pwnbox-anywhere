# Chuyển từ Kali dual boot sang Ubuntu

Sau khi chuyển, desktop chạy **Windows 11 hoặc Ubuntu**. Kali chạy trong VMware
khi Windows đang bật. ThinkPad tiếp tục điều khiển WoL, BootNext, reboot,
shutdown, dashboard và metrics. Khi guest đang chạy, dừng guest trước khi chuyển
từ Windows sang Ubuntu, reboot hoặc tắt Windows.

## 1. Sao lưu và kiểm tra Windows

Sao lưu dữ liệu trên Kali cài trực tiếp và dữ liệu quan trọng trên Windows ra ổ
ngoài. Nếu cần giữ cấu hình dự án, chỉ chép dữ liệu người dùng cần thiết sang VM.
Xác minh VMware vẫn mở được VM cũ trên Windows. Trong máy hiện tại, file VMX là
`D:\Vms\HTB-Kali\kali-linux-2026.1-vmware-amd64.vmx`.
Khi sao lưu VM, tắt guest sạch rồi sao chép cả thư mục VM sang ổ ngoài.

PowerShell **Run as administrator**, tại console Windows:

```powershell
Get-Disk | Format-Table Number,FriendlyName,PartitionStyle,Size
Get-Partition | Format-Table DiskNumber,PartitionNumber,DriveLetter,Type,GptType,Size
bcdedit /enum firmware
manage-bde -status C:
manage-bde -status D:
```

Lưu recovery key cho mọi ổ đã mã hóa ở nơi có thể mở từ thiết bị khác. Dùng boot
menu UEFI chọn trực tiếp **Windows Boot Manager**, xác nhận Windows và ổ D:
mở được, rồi đặt Windows Boot Manager đứng đầu trong UEFI. Nếu bước này lỗi, giữ
nguyên phân vùng và xử lý Windows boot trước.
[Tìm BitLocker recovery key](https://support.microsoft.com/en-us/windows/security/encryption/find-your-bitlocker-recovery-key?linkId=247750814).

Sơ đồ đọc từ Windows tại thời điểm viết hướng dẫn:

| Ổ vật lý | Phân vùng | Thao tác khi cài |
|---|---|---|
| Lexar SSD NQ780 1 TB, Disk 0 | EFI Windows 200 MiB, MSR, C:, Recovery | Giữ cả ổ |
| HP SSD FX900 Plus 2 TB, Disk 1 | Partition 1, NTFS D: `Storage`, chứa VM | Giữ nguyên |
| HP SSD FX900 Plus 2 TB, Disk 1 | Partition 2, EFI khoảng 1 GB | Giữ nguyên, có thể dùng làm ESP Ubuntu |
| HP SSD FX900 Plus 2 TB, Disk 1 | Partition 3, GPT Linux, 321.12 GB (299.07 GiB) | Xác nhận là Kali rồi dùng cho Ubuntu |
| Kingston DataTraveler 64 GB, Disk 2 | USB E: tại thời điểm kiểm tra | Chỉ chọn trong Rufus nếu đúng USB định ghi |

Disk number và tên `/dev/nvme...` có thể đổi sau reboot. Nhận diện bằng model,
kích thước, thứ tự phân vùng và filesystem. Kiểu GPT Linux tự nó chưa xác nhận
nội dung là Kali. EFI trên HP nằm giữa D: và phân vùng Linux, nên khoảng trống
sau khi xóa Linux không liền kề D: để dùng **Extend Volume** trực tiếp.
[Windows Disk Management](https://support.microsoft.com/en-gb/windows/experience/storage-filemanagement/disk-management-in-windows).

## 2. Tạo USB trước khi đụng phân vùng

Tải [Ubuntu Desktop 26.04 LTS amd64](https://ubuntu.com/download/desktop) và
[Rufus](https://rufus.ie/). Dùng USB ít nhất 8 GB và sao lưu dữ liệu trên USB.
Trong Rufus chọn đúng thiết bị USB → **SELECT** ISO → **GPT** / **UEFI (non CSM)**
→ **START**, chọn **ISO Image mode** nếu được hỏi. Mở boot menu UEFI rồi chọn
mục USB UEFI. Chọn **Try Ubuntu** để kiểm tra mạng dây, hình ảnh và SSD.
[Hướng dẫn Rufus của Ubuntu](https://ubuntu.com/desktop/docs/en/latest/how-to/create-a-bootable-usb-stick/).

## 3. Cài Ubuntu vào chỗ Kali

Trong Kali trước khi xóa, hoặc trong phiên Ubuntu live, dùng:

```bash
lsblk -o NAME,MODEL,SIZE,FSTYPE,LABEL,PARTUUID,MOUNTPOINTS
```

Đối chiếu phân vùng Linux khoảng 299 GiB trên SSD HP với phân vùng Kali đã sao
lưu. Trong Kali đang chạy, dùng thêm `findmnt /` và `findmnt /boot/efi` để xác
nhận root và EFI. Nếu chỉ còn USB live và chưa nhận ra nội dung phân vùng Linux,
mở bằng chế độ chỉ đọc để xác nhận trước khi sửa.

1. Từ Ubuntu live, mở **Install Ubuntu → Interactive installation → Manual
   installation**.
2. Chọn đúng phân vùng Kali đã xác nhận. Nếu dùng hết chỗ Kali, sửa phân vùng đó
   thành **ext4**, mount point **/**, bật **format cho đúng phân vùng này**. Nếu
   muốn cấp ít hơn, xóa đúng phân vùng Linux, tạo ext4 **/** với dung lượng mong
   muốn và để phần còn lại **unallocated**. Format/xóa sẽ mất dữ liệu Kali cũ.
3. Nếu màn hình cho chọn EFI, dùng phân vùng EFI khoảng 1 GB sẵn có trên SSD HP
   cho **/boot/efi**, bỏ chọn format. Giữ EFI của Windows trên Lexar. Nếu installer
   báo lỗi hoặc màn hình tổng kết cho thấy thay đổi ngoài dự kiến, quay lại và
   kiểm tra thay vì xác nhận. Tránh **Erase disk** trên cả hai SSD.
4. Nếu gặp cảnh báo BitLocker, dừng ở màn hình đó và kiểm tra ổ installer muốn
   truy cập. Việc dùng phân vùng Linux có sẵn không cần thu nhỏ C: hay D:.
   [Ubuntu và BitLocker](https://ubuntu.com/desktop/docs/en/latest/reference/bitlocker-during-ubuntu-installation/).
5. Xem lại danh sách phân vùng bị format, xác nhận chỉ là phân vùng root Ubuntu
   rồi cài. Sau reboot rút USB, chọn thử entry **ubuntu**, rồi thử **Windows Boot
   Manager**. Đặt lại Windows Boot Manager đứng đầu nếu installer đã đổi thứ tự.
   [Hướng dẫn cài Ubuntu](https://ubuntu.com/desktop/docs/en/latest/tutorial/install-ubuntu-desktop/).

Nếu chọn mã hóa Ubuntu bằng passphrase lúc boot, kiểm tra cách mở khóa trước khi
dựa vào boot từ xa. Controller chỉ xác minh được Ubuntu sau khi SSH đã lên.

## 4. Cập nhật ThinkPad từ repo Windows

Trong PowerShell tại workspace hiện tại, dùng đúng user/hostname ThinkPad nếu
khác mặc định của script:

```powershell
Set-Location D:\Code\pwnbox-anywhere
python setup/build-release.py
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup\update-thinkpad-from-windows.ps1
```

Nếu bản code mới đã có trên ThinkPad thì chạy `bash setup/update-web.sh` ở đó.
Nếu chỉ dùng CLI, chạy `sudo bash setup/setup-thinkpad.sh` trên ThinkPad. Bản
dashboard cập nhật bằng quy trình hiện có và giữ lịch sử, mật khẩu cùng Serve.

Tạo key riêng trên ThinkPad nếu chưa có cặp key tên này. Với controller chạy
không cần người đăng nhập, dùng passphrase trống cho key automation. Chỉ chuyển
file `.pub` sang Ubuntu, chẳng hạn qua một USB dữ liệu.

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_control_ubuntu -C thinkpad-control-ubuntu
```

Trên Ubuntu mới, mở Terminal và lấy source từ GitHub:

```bash
sudo apt update
sudo apt install -y git
git clone https://github.com/dzwng/pwnbox-anywhere.git
cd pwnbox-anywhere
```

Nếu đã có thư mục repo thì vào thư mục đó và chạy `git pull --ff-only`. Nếu
dùng gói release từ Windows, chạy `tar -xzf pwnbox-vmware.tar.gz` rồi
`cd pwnbox-anywhere`. Chạy các lệnh `setup/...` ở bước tiếp theo từ đây.

## 5. Cài Ubuntu endpoint và đổi mapping

Trong Ubuntu đã cài, tại console:

```bash
sudo apt update
sudo apt install efibootmgr
sudo efibootmgr -v
ip -br addr
```

Ghi số **BootNNNN** của **Windows Boot Manager** và **ubuntu** theo loader thật.
Trên Windows, chạy `bcdedit /enum firmware` từ PowerShell Administrator và ghi
**identifier** của entry Ubuntu, thường có path `\EFI\ubuntu\shimx64.efi`.
Số BootNNNN và GUID BCD là hai giá trị khác nhau. Giữ Windows Boot Manager đứng
đầu. Tạo DHCP reservation hoặc dùng IP LAN ổn định cho Ethernet Ubuntu.

Trên Ubuntu, điền ba giá trị thực tế vào biến dưới đây. Tên helper vẫn có
`kali` để dùng chung với profile cũ. Option `--ubuntu-boot-id` chọn Ubuntu.

```bash
WIN_ID=XXXX
UBUNTU_ID=YYYY
THINKPAD_PUB=/path/to/pwnbox_control_ubuntu.pub

sudo bash setup/setup-kali.sh --user "$(id -un)" \
  --windows-boot-id "$WIN_ID" --ubuntu-boot-id "$UBUNTU_ID" \
  --automation-public-key "$THINKPAD_PUB"
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Từ ThinkPad, thay `UBUNTU_USER@UBUNTU_LAN_IP` bằng giá trị thật, so fingerprint
với console trước khi chấp nhận. Nếu SSH dùng cổng riêng, thêm `-p PORT`.

```bash
ssh -F /dev/null -o HostKeyAlias=pwnbox-control-ubuntu \
  -o UserKnownHostsFile=~/.ssh/pwnbox_control_known_hosts -o IdentitiesOnly=yes \
  -i ~/.ssh/pwnbox_control_ubuntu UBUNTU_USER@UBUNTU_LAN_IP status
```

Kết quả cần là `PWNBOX_UBUNTU`. Trên ThinkPad, sao lưu config và sửa các dòng
tương ứng, mỗi key một dòng. Các tên `KALI_*` trong file này chỉ profile Linux
cài trực tiếp. Dùng giá trị thật thay cho placeholder.

```bash
cp -p ~/.config/pwnbox/pwnbox.conf ~/.config/pwnbox/pwnbox.conf.before-ubuntu
nano ~/.config/pwnbox/pwnbox.conf
```

```ini
LINUX_OS=ubuntu
KALI_HOST=UBUNTU_LAN_IP
KALI_USER=UBUNTU_USER
KALI_SSH_PORT=22
KALI_IDENTITY_FILE=~/.ssh/pwnbox_control_ubuntu
WINDOWS_BOOT_ID=XXXX
KALI_BOOT_ID=YYYY
KALI_WINDOWS_BCD_GUID={UBUNTU_FIRMWARE_GUID}
```

Chạy `pwnbox status` và `pwnbox doctor` trên ThinkPad trong lúc Ubuntu đang
chạy. Kết quả cần là `UBUNTU`. Làm mới dashboard, kiểm tra thẻ Ubuntu và
CPU/RAM/disk. Đọc trạng thái WoL trên interface Ethernet Ubuntu bằng
`sudo ethtool TEN_INTERFACE`. Nếu chưa có `Wake-on: g` hoặc mất sau reboot, cấu
hình profile NetworkManager theo [mục WoL](dualboot.md#wol).

## 6. Kết nối Mac và kiểm tra Kali VMware

Trên Ubuntu, [cài Tailscale theo hướng dẫn chính thức](https://tailscale.com/docs/install/linux)
rồi đăng nhập vào đúng tailnet qua URL do lệnh in ra:

```bash
sudo tailscale up --hostname=pwnbox-ubuntu
tailscale ip -4
```

Trên Mac, tạo key interactive riêng nếu chưa có cặp key này:

```zsh
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_ubuntu -C mac-to-ubuntu
```

Chuyển file `.pub` sang Ubuntu. Trong Ubuntu, chạy bằng user tương tác:

```bash
bash setup/setup-kali-interactive.sh /path/to/mac-pwnbox_ubuntu.pub
# Tùy chọn cho desktop từ xa trên Ubuntu
sudo bash pwnbox.sh install
```

Thêm block này vào `~/.ssh/config` trên Mac, thay user và HostName bằng tên/IP
Tailscale thật, rồi xác minh fingerprint trước lần kết nối đầu.

```sshconfig
Host ubuntu pwnbox-ubuntu
    HostName pwnbox-ubuntu
    User UBUNTU_USER
    HostKeyAlias pwnbox-interactive-ubuntu
    IdentityFile ~/.ssh/pwnbox_ubuntu
    IdentitiesOnly yes
```

Trên Mac, từ repo đã cập nhật:

```zsh
mkdir -p ~/.config/pwnbox
cp macos-pwnbox.zsh.example ~/.config/pwnbox/aliases.zsh
```

Trong `~/.zshrc`, đặt hai biến trước dòng `source`. Nếu đã có dòng `source`
thì dùng lại dòng đó. Sau khi lưu, mở terminal mới.

```zsh
PWNBOX_LINUX_OS=ubuntu
PWNBOX_KALI_HOST=ubuntu
source ~/.config/pwnbox/aliases.zsh
```

`pwnbox ssh`, `pwnbox_vnc` (5901) và `proxy_up` (1080) sẽ dùng Ubuntu.
Với VM, tiếp tục dùng `ssh kali-vm`, `pwnbox_vm_vnc` (5902),
`proxy_vm_up` (1081) và profile VM hiện có. Nếu VM đã được điều khiển qua
dashboard, dùng lại `vmware.conf`, task Windows và key VM. Nếu còn trạng thái
**Not configured**, dùng các bước setup Windows/ThinkPad/guest trong
[runbook VMware](vmware.md), trỏ vào VMX hiện có. Nếu thật sự chưa có VM, mở
VMX từ [image VMware chính thức](https://www.kali.org/docs/virtualization/import-premade-vmware/)
và đổi mật khẩu mặc định trước khi cấu hình truy cập.

## 7. Kiểm tra trên máy thật

Thử khi có mặt tại console. Lưu việc đang làm trước mỗi lần đổi OS.

1. Ở Ubuntu, `pwnbox status` trả `UBUNTU`, Mac chạy được `ssh ubuntu`.
2. Từ ThinkPad hoặc Mac, `pwnbox windows` chuyển về Windows. Kiểm tra
   `bcdedit /enum '{fwbootmgr}'` còn Windows Boot Manager đứng đầu.
3. Khi Windows user của task đã đăng nhập, thử `pwnbox vm-start`,
   `pwnbox vm-status` (RUNNING) và `ssh kali-vm` từ Mac. Chạy
   `pwnbox vm-stop` rồi xác nhận VM STOPPED và desktop vẫn WINDOWS.
4. `pwnbox bootnext-ubuntu` chỉ chọn lần boot tiếp theo. Thử
   `pwnbox reboot-ubuntu` hoặc `pwnbox ubuntu` để chuyển và xác minh Ubuntu.
5. Từ Ubuntu, thử `pwnbox off` rồi `pwnbox wake`. Máy phải thức dậy vào
   Windows mặc định. Thử lại nút Ubuntu và thẻ VMware trên dashboard.

Nếu một bước lỗi, kiểm tra console và `pwnbox doctor` trước khi gửi lại lệnh.
Entry Kali cũ trong UEFI có thể để lại trong lúc kiểm tra Ubuntu/Windows.
