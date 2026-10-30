# Run in an interactive PowerShell terminal; SSH/sudo may ask for passwords.
[CmdletBinding()]
param(
    [string]$Relay = 'zwng@pwnbox-relay',
    [string]$Archive
)
$ErrorActionPreference = 'Stop'
if (-not $PSBoundParameters.ContainsKey('Archive')) {
    $Archive = Join-Path $PSScriptRoot '..\.local\releases\pwnbox-vmware.tar.gz'
}
if ($Relay -notmatch '^[a-zA-Z0-9_.-]+@[a-zA-Z0-9_.-]+$') { throw 'Use user@hostname for -Relay.' }
$Archive = (Resolve-Path -LiteralPath $Archive).Path
$checksum = "$Archive.sha256"
$digest = (Get-Content -LiteralPath $checksum -Raw).Split(' ')[0].Trim()
if ($digest -notmatch '^[a-f0-9]{64}$' -or
    (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $digest) { throw 'Archive checksum mismatch.' }
if ((Split-Path -Leaf $Archive) -ne 'pwnbox-vmware.tar.gz') { throw 'Expected pwnbox-vmware.tar.gz.' }
& scp -o StrictHostKeyChecking=yes $Archive $checksum "${Relay}:./"
if ($LASTEXITCODE -ne 0) { throw 'Upload failed; nothing installed.' }
$command = @'
set -eu
cd "$HOME"
sha256sum -c pwnbox-vmware.tar.gz.sha256
mkdir -p "$HOME/.local/share/pwnbox"
work=$(mktemp -d "$HOME/.local/share/pwnbox/vmware-update.XXXXXX")
tar -xzf pwnbox-vmware.tar.gz -C "$work"
if [ -d /usr/local/lib/pwnbox ]; then
    tar -czf "$work/installed-before.tar.gz" -C /usr/local/lib pwnbox
fi
printf 'Code backup and extracted source: %s\n' "$work"
cd "$work/pwnbox-anywhere"
bash setup/update-web.sh
printf 'Next steps: %s/docs/vmware.md\n' "$work/pwnbox-anywhere"
'@
$command = $command -replace "`r", ''
& ssh -t -o StrictHostKeyChecking=yes $Relay $command
if ($LASTEXITCODE -ne 0) { throw 'Update incomplete. Review terminal output; no power action was sent.' }
