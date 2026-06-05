# Cross-platform free-space helpers used to preflight writes (firmware/ROMs/cores) so we
# never start a copy that cannot finish and leave the card half-written.

function Get-PocketFreeSpace {
    # Available bytes on the volume that contains $Path. Works on Windows (drive letters)
    # and Linux/macOS (mount points) by matching the DriveInfo whose RootDirectory is the
    # longest prefix of the resolved path.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)

    $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $best = $null
    $bestLen = -1
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady) { continue }
        $root = $d.RootDirectory.FullName
        if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -and $root.Length -gt $bestLen) {
            $best = $d; $bestLen = $root.Length
        }
    }
    if (-not $best) {
        throw "Could not determine free space for '$full'."
    }
    return [int64]$best.AvailableFreeSpace
}

function Assert-PocketFreeSpace {
    # Throws a clear error if $RequiredBytes will not fit in the free space at $Root.
    # $AvailableBytes can be supplied (testing) to bypass the live query.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [int64]  $RequiredBytes,
        [string] $Label = 'these files',
        [Nullable[int64]] $AvailableBytes,
        [switch] $Skip
    )
    if ($Skip -or $RequiredBytes -le 0) { return }

    $avail = if ($null -ne $AvailableBytes) { [int64]$AvailableBytes } else { Get-PocketFreeSpace -Path $Root }
    if ($RequiredBytes -gt $avail) {
        $needMB = [math]::Round($RequiredBytes / 1MB, 1)
        $haveMB = [math]::Round($avail / 1MB, 1)
        throw "Not enough free space on '$Root' for ${Label}: need ${needMB} MB but only ${haveMB} MB free. Free up space or use a larger card."
    }
}
