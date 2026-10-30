# Dùng đồng thời Kali dual boot và Kali VMware

Dashboard có **Start Kali dual boot** và **Kali VMware → Start / Stop VM only**.
Hai lựa chọn cùng tồn tại trên dashboard. Trên phần cứng, Windows + Kali VMware
chạy đồng thời; Kali dual boot chiếm desktop nên không chạy cùng Windows/VMware.

VM cũ của bạn là **HTB-Kali**:

```text
D:\Vms\HTB-Kali\kali-linux-2026.1-vmware-amd64.vmx
```

File `.vmdk` cùng thư mục là ổ đĩa. Không đưa `.vmdk` vào task, không tạo VM mới,
không di chuyển/copy ổ đĩa để phục hồi workflow. Node Tailscale guest: `kali-vmware`.
Kiểm tra read-only trong phiên bổ sung này thấy task **Wake Kali VM** còn tồn tại,
đúng VMX/user `hband`, và VMware báo 0 VM chạy. Đây là ảnh chụp thời điểm kiểm tra.

## Những phần được tách riêng

| Thành phần | Kali dual boot hiện có | Kali VMware |
|---|---|---|
| Lệnh điều khiển ThinkPad | `pwnbox kali`, `pwnbox off` | `pwnbox vm-start`, `pwnbox vm-stop` |
| Ý nghĩa lệnh dừng | Tắt cả desktop | Tắt guest, giữ Windows |
| Tailscale guest/OS | `pwnbox-kali` | `kali-vmware` |
| SSH alias Mac | `kali`, `pwnbox-kali` | `kali-vm`, `kali-vmware` |
| Interactive key Mac | `pwnbox_kali` | `pwnbox_kali_vm` |
| Automation key ThinkPad | `pwnbox_control_kali` | `pwnbox_control_kali_vm` |
| Config ThinkPad | `pwnbox.conf` | `vmware.conf` |
| HostKeyAlias automation | `pwnbox-control-kali` | `pwnbox-control-kali-vm` |
| Known hosts automation | `pwnbox_control_known_hosts` | `pwnbox_vm_known_hosts` |
| Forced command guest | `pwnbox-kali-control` | `pwnbox-kali-vm-control` |
| Cổng VNC localhost trên Mac | `5901` | `5902` → guest `5901` |
| Cổng SOCKS localhost trên Mac | `1080` | `1081` |

Giữ nguyên key Windows automation và key Mac → ThinkPad đang hoạt động. Không cần
rotate key dual boot. Hai key VM mới giúp thu hồi quyền từng môi trường độc lập.
`kali_up`, `kali_down`, `pwnbox_down` vẫn giữ nghĩa v2; **không dùng chúng để dừng VM**.

## 1. Chuẩn bị code trên từng máy

Dùng cùng bản repository mới trên ThinkPad, Windows và guest. Gói release kèm
toàn bộ script, aliases và tài liệu, không chứa `.local`, key hoặc config riêng.
Không chạy `legacy/setup-windows.ps1` hay legacy uninstall để phục hồi: các script
đó còn thay đổi SSH/WoL và có thể làm hỏng cấu hình đã kiểm thử của dual boot.

Nếu dùng gói từ Windows, từ thư mục project chạy:

```powershell
python setup/build-release.py
powershell -ExecutionPolicy Bypass -File setup/update-thinkpad-from-windows.ps1
```

Script upload hỏi mật khẩu SSH/sudo trong terminal, xác minh checksum rồi cập nhật
web/controller. Không gửi reboot/start VM. Bản mới giữ mục Websites on ThinkPad từ gói
course trước đây, đọc `sites.json` và Tailscale Serve hiện có. Installer thay code
web bằng bản trong gói; nếu có tùy chỉnh khác ngoài repository thì merge trước.
Có backup code trước cập nhật.
Mật khẩu dashboard, SQLite history, controller config/key và Tailscale Serve được giữ.

Nếu code mới đã có trên ThinkPad, chạy từ user controller hiện tại (`zwng`):

```bash
bash setup/update-web.sh
```

Dashboard hiện thẻ VMware ở trạng thái **Not configured** cho đến khi hoàn tất các
bước sau. Có thể cập nhật giao diện trước; dual boot vẫn hoạt động khi chưa có profile VM.

## 2. ThinkPad: tạo key automation dành riêng cho VM

Chưa cần bật VM tự động. Trên ThinkPad, tại thư mục code mới, chạy bằng user controller,
**không sudo**. Thay `VM_USER` bằng kết quả `whoami` trong console HTB-Kali:

```bash
bash setup/prepare-vmware-thinkpad.sh VM_USER
```

Script tạo key không passphrase cho unattended control nếu chưa tồn tại, giữ key/config
cũ nếu đã có. Profile ban đầu `VM_ENABLED=false`, host mặc định `kali-vmware`.
Chỉ copy `~/.ssh/pwnbox_control_kali_vm.pub` sang guest; private key ở lại ThinkPad.
Không sửa `KALI_HOST` trong `pwnbox.conf` thành địa chỉ VM.

## 3. MacBook: key interactive mới và alias riêng

Trên Mac, tạo key **chỉ khi cả hai file tên này chưa tồn tại**:

```zsh
ls -l ~/.ssh/pwnbox_kali_vm ~/.ssh/pwnbox_kali_vm.pub
# Nếu chưa có cả hai:
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pwnbox_kali_vm -C mac-to-kali-vm
```

Nếu đã có key hợp lệ thì dùng lại, không ghi đè. Copy **file `.pub`** tới guest bằng
console/shared folder hoặc SCP với tài khoản guest hiện có. Không copy private key.
Merge [SSH config VM](../config/ssh-macos-vmware.conf.example) vào `~/.ssh/config`,
điền user guest. Giữ nguyên block `Host kali pwnbox-kali` hiện có; không thêm `kali`
vào block VM. Đặt block cụ thể trước `Host *`, merge block trùng thay vì append mù.

## 4. Kali VMware: phục hồi endpoint và GUI

Mở **HTB-Kali** bằng VMware trên Windows một lần để cấu hình. Trong console guest:

```bash
whoami
systemd-detect-virt --vm                 # phải là vmware
tailscale status
tailscale ip -4
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Node phải là `kali-vmware`, khác node dual boot. Nếu Tailscale cũ vẫn đăng nhập và
đúng tên thì giữ nguyên. Nếu node cũ đã bị xóa/hết hạn, đăng nhập lại ngay **trong VM**;
không copy `/var/lib/tailscale` từ dual boot hoặc một VM clone. Nếu cần đổi tên:
`sudo tailscale set --hostname=kali-vmware`. Kiểm tra MagicDNS không có node trùng tên.
ThinkPad dùng địa chỉ Tailscale VM này nên NAT/bridged không cần dùng chung IP desktop;
Mac cũng kết nối trực tiếp tới VM qua Tailscale. Không cần mở port router.

Tại thư mục repo mới trong VM, cài với đúng user và hai public key ở bước 2–3:

```bash
sudo bash setup/setup-kali-vm.sh VM_USER /path/thinkpad-vm.pub /path/mac-vm.pub
```

Script chỉ chấp nhận Kali chạy trong VMware. Nó giữ các SSH key khác, backup
`authorized_keys`, cài forced command **status/off** và sudoers chỉ cho shutdown guest.
Không cài EFI/BootNext, không đụng cấu hình endpoint của Kali bare metal.
Nếu key đã có với quyền/options khác, script dừng để review thay vì tự đổi quyền key.

GUI tùy chọn, chạy từ phiên login của đúng user guest để cài helper VNC mới:

```bash
sudo bash pwnbox.sh install --vmware-tools
pwnbox-kali vnc status
```

Installer giữ VNC password hiện có nếu không có `--reset-vnc-password`. Helper mới
là `pwnbox-kali`, khác controller `pwnbox` trên ThinkPad. File `/usr/local/bin/pwnbox`
legacy trong VM có thể giữ để đối chiếu; Mac mới gọi `pwnbox-kali`. Nếu có service
`vncserver@1` cũ chiếm display `:1`, xem [GUI/browser](gui-and-browser.md) trước khi
tắt riêng service đó. Không cần bật LightDM autologin trong guest để VNC hoạt động.

## 5. Windows: cài adapter VMware mới, giữ setup cũ

PowerShell **Run as administrator**, trong repo mới:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup\setup-vmware-windows.ps1 `
  -VmxPath 'D:\Vms\HTB-Kali\kali-linux-2026.1-vmware-amd64.vmx' `
  -WindowsUser "$env:COMPUTERNAME\hband"
```

Script kiểm tra file/vmrun, lưu helper và config ở `%ProgramData%\pwnbox` với ACL
Administrators/SYSTEM, backup bản trước, tạo task **Pwnbox Kali VMware** chạy interactive
`vmrun -T ws start "...vmx" gui`. Không có trigger tự bật VM mỗi lần boot Windows.
Không sửa OpenSSH/key/firewall/WoL/Fast Startup, không start guest hoặc reboot khi cài.
Task `Wake Kali VM` được giữ; sau khi test xong có thể chạy lại cùng lệnh với
`-DisableLegacyTask` để backup XML và disable riêng task cũ.

Giữ Windows user `hband` logged in; lock màn hình vẫn được, **sign out thì task GUI
không chạy**. Cold boot unattended tiếp tục cần Sysinternals Autologon đã dùng trước
đây. Nếu autologon đã tắt, cấu hình lại bằng UI Sysinternals Autologon theo
[runbook legacy](../legacy/automating-startup.md), không ghi password vào script.
Installer mới không tự đặt autologon. Nếu `vmrun list` lỗi tại Windows desktop thật,
kiểm tra/repair VMware trước; không coi lỗi inventory là VM đã tắt.

## 6. Xác minh host key, rồi bật profile trên ThinkPad

So fingerprint in từ **console VM ở bước 4** trước khi chấp nhận key lần đầu:

```bash
ssh -F /dev/null -o IdentitiesOnly=yes \
  -o HostKeyAlias=pwnbox-control-kali-vm \
  -o UserKnownHostsFile=~/.ssh/pwnbox_vm_known_hosts \
  -i ~/.ssh/pwnbox_control_kali_vm VM_USER@kali-vmware status
```

Mong đợi `PWNBOX_KALI_VM`. Lần kết nối đầu yêu cầu so fingerprint; các lệnh controller
sau đó luôn `StrictHostKeyChecking=yes` và `BatchMode=yes`. Không lấy fingerprint của
Kali dual boot thay cho VM, không dùng `StrictHostKeyChecking=no`.

Sửa `~/.config/pwnbox/vmware.conf`: đặt `VM_USER` đúng, `VM_HOST=kali-vmware` hoặc IP
Tailscale riêng của guest, và **VM_ENABLED=true**. `chmod 600` file này. Không quote
giá trị và không thêm inline comment. Không sửa profile dual boot. Sau đó:

```bash
pwnbox status                 # WINDOWS khi guest chạy trên Windows
pwnbox vm-doctor              # RUNNING, kèm địa chỉ guest; lỗi SSH ở stderr
pwnbox vm-status              # RUNNING
```

Controller dùng key Windows đang có để đọc inventory/call task. Nếu Windows áp dụng
Execution Policy bằng Group Policy khiến helper không chạy, `vm-doctor` báo UNKNOWN;
giải quyết policy tại Windows theo quản trị hiện có, không bỏ qua lỗi để báo STOPPED.
Không cần restart web khi chỉ sửa profile; backend đọc lại mỗi lần kiểm tra/lệnh.

## 7. MacBook: cập nhật helpers và kiểm tra đích

Copy repo/gói mới tới Mac. Backup aliases trước khi thay; merge tùy chỉnh cá nhân
nếu bản hiện tại có chỉnh thêm:

```zsh
cp -p ~/.config/pwnbox/aliases.zsh ~/.config/pwnbox/aliases.before-vmware.zsh
cp macos-pwnbox.zsh.example ~/.config/pwnbox/aliases.zsh
source ~/.config/pwnbox/aliases.zsh
ssh -G kali | awk '/^(hostname|user|identityfile|hostkeyalias) /'
ssh -G kali-vm | awk '/^(hostname|user|identityfile|hostkeyalias) /'
ssh kali-vm whoami
```

Kết nối đầu `ssh kali-vm` cũng phải so fingerprint VM; fingerprint lưu dưới alias
`pwnbox-interactive-kali-vm`. `kali` phải vẫn trỏ `pwnbox-kali`; `kali-vm` trỏ
`kali-vmware`. Key passphrase dùng ssh-agent/Keychain hiện có của Mac.

| Công việc | Dual boot | VMware |
|---|---|---|
| Bật | `pwnbox kali` | `pwnbox vm-start` / `pwnbox_vm_up` |
| SSH | `ssh kali` | `ssh kali-vm` / `pwnbox vm-ssh` |
| VNC | `pwnbox_vnc` | `pwnbox_vm_vnc` |
| Mở viewer | `open vnc://127.0.0.1:5901` | `open vnc://127.0.0.1:5902` |
| Ngắt tunnel, giữ desktop | `pwnbox_vnc_disconnect` | `pwnbox_vm_vnc_disconnect` |
| Kết thúc phiên VNC | `pwnbox_vnc_stop` | `pwnbox_vm_vnc_stop` |
| SOCKS lên/xuống | `proxy_up` / `proxy_down` | `proxy_vm_up` / `proxy_vm_down` |
| SCP lên/xuống | `kali_push` / `kali_pull` | `kali_vm_push` / `kali_vm_pull` |
| Dừng | `pwnbox off` (cả PC) | `pwnbox vm-stop` / `pwnbox_vm_down` (chỉ VM) |

Firefox nên có profile **HTB-VM** riêng: SOCKS v5 `127.0.0.1:1081`, DNS qua SOCKS,
DoH off, như profile dual boot dùng cổng 1080. VPN HTB, `/etc/hosts`, loot, VNC password
và tool config bên trong hai Kali là dữ liệu độc lập; phục hồi workflow không tự
đồng bộ chúng. `proxy_vm_down` không dừng VPN/guest; VNC disconnect không tắt guest.

## Trạng thái, kiểm thử thật và xử lý lỗi

| VMware state | Ý nghĩa / xử lý |
|---|---|
| DISABLED | Chưa có profile hoặc `VM_ENABLED=false`; dual boot vẫn dùng được |
| STOPPED | Windows SSH đã xác minh, inventory hợp lệ không chứa đúng VMX, guest không xác minh online |
| RUNNING | Inventory chứa đúng VMX và SSH trả đúng marker `PWNBOX_KALI_VM` |
| GUEST_UNREACHABLE | VM đang có trong inventory nhưng guest SSH/key/marker chưa xác minh; kiểm tra console |
| HOST_UNAVAILABLE | Desktop đã xác minh Kali dual boot hoặc OFF suy luận; không phải trạng thái nguồn đo của guest |
| UNKNOWN / CONFIG_ERROR | Không đủ chứng cứ hoặc profile sai; `pwnbox vm-doctor` xem lỗi cụ thể |

Không dùng việc SSH guest mất kết nối làm bằng chứng VM đã tắt. Nếu guest không SSH
được, shutdown sạch trong console VMware, rồi kiểm tra `vm-status`. Không có fallback
hard stop. `vm-start` không lặp task khi guest đã powered on nhưng chưa SSH được;
nó chờ với timeout. Task được nhận không có nghĩa guest đã boot thành công.

Sau khi lưu công việc, test lần lượt trên dashboard/CLI:

1. Windows + VM: `status` phải WINDOWS, `vm-status` RUNNING; SSH `kali-vm` đúng guest.
2. `vm-stop`: guest dừng, Windows còn SSH/AnyDesk, dashboard host vẫn Windows.
3. `vm-start` hai lần: lần hai giữ guest/session; không tạo instance khác.
4. Khi VM chạy, `kali`, `off` và `reboot-*` bị từ chối trước power/firmware action;
   dừng VM trước rồi thực hiện lệnh host. Set BootNext vẫn được vì chưa reboot.
5. Desktop đang Kali dual boot: `vm-stop` không reboot desktop; `vm-start` chuyển về
   Windows rồi start VM (đóng công việc bare metal, cần xác nhận trên dashboard).
6. Cold boot: thử riêng sau khi xác minh autologon; guest phải lên qua task rồi SSH.
7. Mac VNC 5902/SOCKS 1081 đúng VM; 5901/1080 và các helper cũ vẫn dành cho dual boot.

Mọi lệnh ghi dùng chung `operation.lock` với controller dual boot; history, xác nhận,
CSRF và request idempotency của dashboard áp dụng cho cả hai mode. Status guest đọc
khoảng 30 giây khi dashboard hoạt động, cập nhật sau job. System health là metrics
**Windows host hoặc Kali bare metal**, không gắn metrics host thành metrics VM.
Không có benchmark/tuyên bố kiểm thử reboot máy thật cho phần VMware mới.

Kiểm thử code bằng endpoint giả (không điều khiển máy thật):

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
bash tests/test-orchestration.sh
bash tests/test-vmware.sh
bash tests/test-kali-vm-control.sh
bash tests/test-macos-vmware.sh
bash tests/test-vnc-reconnect.sh
node tests/test-dashboard.cjs
```

Windows helper tests dùng PowerShell mock; trên Linux sẽ skip nhóm Windows.
Git Bash cần `PWNBOX_TEST_PYTHON` trỏ Python thật nếu `python3` là Microsoft Store alias.
Native `flock` được kiểm tra trên Debian; Git Bash dùng shim cho nhánh từ chối lock.

Tắt tích hợp mới: shutdown guest, đặt `VM_ENABLED=false`. Để giữ bảo vệ guest, chỉ
tắt profile khi guest đã dừng. Task/file helper có thể giữ để khôi phục; không chạy
legacy uninstall. Trên Mac, giữ hai bộ aliases tách biệt; nếu bỏ tích hợp thì chỉ
thu hồi public key VM tương ứng ở guest và xóa block VM sau khi đóng tunnel.

Tham khảo cú pháp `vmrun start ... gui`/inventory trong
[VMware Workstation Pro manual](https://techdocs2-prod.adobecqms.net/content/dam/broadcom/techdocs/us/en/pdf/vmware/desktop-hypervisors/workstation/vmware-workstation-pro-17-0.pdf).
