# BootOrder và Windows mặc định

Nếu desktop bật lên luôn vào Kali, đọc firmware trước khi thay đổi.
Trên Windows, mở PowerShell **Run as administrator**:

```powershell
bcdedit /enum firmware
```

`displayorder` dưới `{fwbootmgr}` là thứ tự lâu dài. Nếu entry Kali đứng trước
`{bootmgr}`, Windows chưa là ưu tiên đầu. `bootsequence`, nếu có, là lựa chọn cho
lần boot kế tiếp; không suy ra trạng thái này từ dropdown của Control Center.

Để khôi phục ưu tiên Windows khi đã xác minh đúng entry `{bootmgr}`:

```powershell
bcdedit /set '{fwbootmgr}' displayorder '{bootmgr}' /addfirst
bcdedit /enum '{fwbootmgr}'
```

Kết quả cần có `{bootmgr}` đầu `displayorder`. Giữ nguyên entry Kali và các entry
còn lại. Nếu `bootsequence` đang trỏ sang Kali và muốn hủy lựa chọn một lần đó,
dùng `bcdedit /deletevalue '{fwbootmgr}' bootsequence` rồi đọc lại. Không chạy bước
xóa này khi không có `bootsequence` chỉ để xử lý một lỗi thứ tự lâu dài.

Nguồn: [Microsoft UEFI boot settings](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/bcd-system-store-settings-for-uefi?view=windows-11),
[BCDEdit /deletevalue](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--deletevalue).

## Chẩn đoán sau cập nhật

History trước bản kiểm tra BootOrder chỉ xác minh OS trả lời SSH. Nó không ghi
thứ tự firmware, nên một job “Verified successfully” cũ không chứng minh BootOrder
được giữ nguyên và không cho biết thao tác nào gây đảo thứ tự.

Bản mới ghi trong Operation details:

- BootOrder trước khi controller gửi thao tác và trước khi endpoint đặt BootNext.
- BootOrder ngay sau khi đặt BootNext, trước reboot; so sánh toàn bộ thứ tự trên cùng OS.
- BootOrder và `Windows first` sau khi OS đích sẵn sàng qua SSH.

Windows thể hiện entry bằng BCD identifier, Kali bằng EFI ID: đối chiếu mapping
config trước khi so sánh hai OS. Kiểm tra sau reboot xác minh ưu tiên Windows;
không chứng minh tác nhân cụ thể nếu thứ tự đổi trong khoảng máy reboot.
Nếu đổi ngay khi đặt BootNext, helper dừng trước reboot. Nếu sau boot Windows không
đứng đầu, controller ghi job thất bại và không tự sửa BootOrder hoặc reboot thêm.

Lưu chi tiết job có `Windows first: false` hoặc hai snapshot khác nhau, cùng
`bcdedit /enum firmware` trên Windows hoặc `sudo efibootmgr -v` trên Kali. Đọc lại
thứ tự sau một vòng boot sử dụng bình thường để xác minh trên phần cứng thực;
không tự chạy các vòng reboot/shutdown thử nghiệm chỉ để tìm nguyên nhân.

## Cập nhật

Gói kiểm tra BootOrder yêu cầu helper Kali có lệnh read-only `firmware`:

1. Khi Kali đang chạy, giải nén gói mới và chạy từ thư mục repository:

   ```bash
   sudo bash setup/update-kali-control.sh
   ```

   Lần nâng cấp BootNext trước đã lưu Kali ID; script tái sử dụng ID đó. Nếu chưa có,
   truyền `--kali-boot-id` với ID đã xác minh qua `sudo efibootmgr -v`.

2. Cập nhật ThinkPad từ cùng gói: `bash setup/update-web.sh`, hoặc script
   `UPDATE-FROM-WINDOWS.ps1` đi kèm gói release trong terminal Windows tương tác.

Cài đặt không gửi thao tác firmware hay reboot. Password/history/Tailscale routes
được giữ. Nếu chưa nâng cấp helper Kali, audit không khả dụng khi boot vào Kali;
job sẽ không được đánh dấu thành công hoàn toàn. OS có thể đã boot xong: kiểm tra
trạng thái và nâng cấp helper trước khi thử lại, không bấm lặp lại power action.
