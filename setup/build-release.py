"""Build a source-only VMware/dashboard bundle. Never include local config/keys."""
import hashlib
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".local/releases/pwnbox-vmware.tar.gz"


def build():
    files = [ROOT / name for name in ("README.md", "LICENSE", "pwnbox.sh", "macos-pwnbox.zsh.example",
                                    "setup-windows.ps1", "debian-relay.md", "remote-control.md")]
    for folder, patterns in {
        "bin": ("pwnbox", "pwnbox-metrics", "pwnbox-diagnostics"),
        "lib": ("*.sh",), "web": ("*.py", "*.ps1"),
        "web/static": ("*.js", "*.css", "*.html", "*.svg"),
        "setup": ("*.sh", "*.ps1", "*.py", "pwnbox-kali-control", "pwnbox-kali-vm-control"),
        "config": ("*.example",), "docs": ("*.md",),
        "tests": ("*.py", "*.sh", "*.ps1", "*.cjs"),
        "legacy": ("automating-startup.md",),
    }.items():
        for pattern in patterns:
            files.extend((ROOT / folder).glob(pattern))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(OUTPUT, "w:gz") as archive:
        for path in sorted(set(files)):
            relative = path.relative_to(ROOT)
            if path.is_symlink() or not path.is_file() or any(part.startswith(".") for part in relative.parts):
                raise ValueError(f"Unexpected release input: {relative}")
            info = archive.gettarinfo(str(path), "pwnbox-anywhere/" + relative.as_posix())
            info.mode = 0o755 if relative.parts[0] == "bin" or path.suffix == ".sh" or path.name.startswith("pwnbox-kali-") else 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            with path.open("rb") as stream:
                archive.addfile(info, stream)
    digest = hashlib.sha256(OUTPUT.read_bytes()).hexdigest()
    Path(str(OUTPUT) + ".sha256").write_text(digest + "  " + OUTPUT.name + "\n", encoding="ascii")
    print(f"Created {OUTPUT} ({len(set(files))} files)\nSHA256 {digest}")


if __name__ == "__main__":
    build()
