# Remote control quick reference

Hướng dẫn clean-install đầy đủ nằm trong [README.md](./README.md). File function mẫu cho Mac nằm tại [macos-pwnbox.zsh.example](./macos-pwnbox.zsh.example).

## Bật hệ thống

```bash
pc_up
kali_up
pwnbox_ssh
```

Hoặc:

```bash
pwnbox_up
pwnbox_ssh
```

## Browser port-forward

```bash
ssh -N -L 8080:127.0.0.1:8080 pwnbox-kali
```

## VNC

```bash
pwnbox_vnc
pwnbox_vnc_stop
```

## Tắt hệ thống

```bash
kali_down
pc_down
```

Hoặc:

```bash
pwnbox_down
```

Thứ tự shutdown luôn là Kali trước, Windows sau.
