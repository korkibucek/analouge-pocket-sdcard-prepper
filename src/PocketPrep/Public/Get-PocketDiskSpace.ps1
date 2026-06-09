function Get-PocketDiskSpace {
<#
.SYNOPSIS
    Returns free and total bytes for the volume containing a path.

.DESCRIPTION
    Cross-platform (Windows drive letters, Linux/macOS mount points) - matches the DriveInfo
    whose root is the longest prefix of the resolved path, like the internal free-space
    preflight. Returns nulls (rather than throwing) when the volume can't be determined, so
    UI callers can degrade gracefully.

.PARAMETER Path
    A path on the volume of interest (e.g. the SD card root).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    $result = [pscustomobject]@{
        PSTypeName = 'PocketPrep.DiskSpace'
        Path       = $Path
        FreeBytes  = $null
        TotalBytes = $null
        UsedBytes  = $null
    }
    try {
        $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch { return $result }

    $best = $null; $bestLen = -1
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady) { continue }
        $root = $d.RootDirectory.FullName
        if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -and $root.Length -gt $bestLen) {
            $best = $d; $bestLen = $root.Length
        }
    }
    if ($best) {
        $result.FreeBytes  = [int64]$best.AvailableFreeSpace
        $result.TotalBytes = [int64]$best.TotalSize
        $result.UsedBytes  = [int64]($best.TotalSize - $best.AvailableFreeSpace)
    }
    return $result
}
