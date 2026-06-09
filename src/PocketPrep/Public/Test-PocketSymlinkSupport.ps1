function Test-PocketSymlinkSupport {
<#
.SYNOPSIS
    Reports whether the filesystem at Root can create symbolic links.

.DESCRIPTION
    The Analogue Pocket SD card is FAT32/exFAT, which support no symlinks, and the Pocket
    firmware only reads FAT/exFAT - so on a real card this returns $false and callers must
    copy instead. On a dev/test filesystem (NTFS/ext4/APFS, and with sufficient privilege)
    it may return $true, letting favourites be linked instead of duplicated.

    The probe actually attempts to create (and then remove) a symlink in a temp subfolder of
    Root, so it reflects real capability (filesystem + privilege), not a guess.

.PARAMETER Root
    SD card root or fake SD root folder.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $false }
    $probeDir = Join-Path $Root ('.pp-symlink-probe-' + [System.IO.Path]::GetRandomFileName())
    $target = Join-Path $probeDir 'target.txt'
    $link   = Join-Path $probeDir 'link.txt'
    try {
        New-Item -ItemType Directory -Path $probeDir -Force -ErrorAction Stop | Out-Null
        'probe' | Set-Content -LiteralPath $target -ErrorAction Stop
        $li = New-Item -ItemType SymbolicLink -Path $link -Value $target -ErrorAction Stop
        # Confirm it really is a reparse point/symlink, not a silently-created copy.
        $ok = [bool]($li.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -or ($li.LinkType -eq 'SymbolicLink')
        return $ok
    } catch {
        return $false
    } finally {
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
