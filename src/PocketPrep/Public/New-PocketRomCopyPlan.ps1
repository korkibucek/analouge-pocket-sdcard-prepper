function New-PocketRomCopyPlan {
<#
.SYNOPSIS
    Builds (but does not execute) a plan to copy a system's ROMs to the SD card.

.DESCRIPTION
    Pure planning function. Given a system object and a source folder, it matches
    files by the system's supported extensions and computes destination paths under
    Assets/<platformId>/common. Nothing is copied here - call Invoke-PocketRomCopyPlan.

    This tool copies USER-PROVIDED ROMs only. It never downloads or supplies ROMs,
    and it does not copy BIOS files unless you explicitly opt in elsewhere.

.PARAMETER System
    A system object from Get-PocketSystem.

.PARAMETER SourceFolder
    Folder containing the user's ROM files.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PreserveStructure
    Keep subfolder layout under the destination. Default is to flatten, which is
    what most cores expect.

.PARAMETER Recurse
    Search subfolders of SourceFolder for ROMs.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $System,

        [Parameter(Mandatory)]
        [string] $SourceFolder,

        [Parameter(Mandatory)]
        [string] $Root,

        [switch] $PreserveStructure,

        [switch] $Recurse
    )

    if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
        throw "Source ROM folder not found: $SourceFolder"
    }

    $destRoot = Join-Path (Join-Path (Join-Path $Root 'Assets') $System.PlatformId) 'common'
    $exts = $System.SupportedExtensions

    $allFiles = Get-ChildItem -LiteralPath $SourceFolder -File -Recurse:$Recurse -ErrorAction SilentlyContinue
    $matched  = $allFiles | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() }

    $sourceFull = (Resolve-Path -LiteralPath $SourceFolder).Path

    # Characters that are invalid in FAT32/exFAT file names (besides the path separators).
    $invalidFatChars = [char[]]('<', '>', ':', '"', '|', '?', '*') + @(0..31 | ForEach-Object { [char]$_ })
    $seenDest = @{}

    $items = foreach ($f in $matched) {
        if ($PreserveStructure -and $Recurse) {
            $rel = $f.FullName.Substring($sourceFull.Length).TrimStart([char]'\', [char]'/')
            $dest = Join-Path $destRoot $rel
        } else {
            $rel = $f.Name
            $dest = Join-Path $destRoot $f.Name
        }

        # Detect problems that would otherwise fail or silently clobber on the card.
        $problem = $null
        $leaf = Split-Path -Leaf $dest
        if ($leaf.IndexOfAny($invalidFatChars) -ge 0) {
            $problem = "name contains characters not allowed on FAT/exFAT"
        } elseif ($dest.Length -gt 259) {
            $problem = "destination path is too long (>259 chars)"
        } else {
            $key = $dest.ToLowerInvariant()
            if ($seenDest.ContainsKey($key)) {
                $problem = "duplicate destination name (collides with $($seenDest[$key]))"
            } else {
                $seenDest[$key] = $f.Name
            }
        }

        [pscustomobject]@{
            Source       = $f.FullName
            Destination  = $dest
            RelativePath = $rel
            SizeBytes    = $f.Length
            Problem      = $problem
        }
    }
    $items = @($items)
    $problemItems = @($items | Where-Object { $_.Problem })
    $copyableItems = @($items | Where-Object { -not $_.Problem })
    # Free-space requirement is based only on files that will actually be copied.
    $totalBytes = [int64]((($copyableItems | Measure-Object -Property SizeBytes -Sum).Sum) ?? 0)

    # Best-effort free-space info so callers can warn before executing the copy.
    $freeBytes = $null
    try { $freeBytes = Get-PocketFreeSpace -Path (Resolve-Path -LiteralPath $Root).Path } catch { $freeBytes = $null }
    $fits = if ($null -ne $freeBytes) { $totalBytes -le $freeBytes } else { $true }

    [pscustomobject]@{
        PSTypeName         = 'PocketPrep.RomCopyPlan'
        Root               = (Resolve-Path -LiteralPath $Root).Path
        SystemId           = $System.Id
        SystemDisplayName  = $System.DisplayName
        PlatformId         = $System.PlatformId
        SourceFolder       = $sourceFull
        Destination        = $destRoot
        Flatten            = (-not $PreserveStructure)
        FileCount          = $items.Count
        CopyableCount      = $copyableItems.Count
        ProblemCount       = $problemItems.Count
        Problems           = @($problemItems | ForEach-Object { [pscustomobject]@{ Source = $_.Source; RelativePath = $_.RelativePath; Reason = $_.Problem } })
        TotalBytes         = $totalBytes
        DestinationFreeBytes = $freeBytes
        FitsInDestination  = $fits
        SkippedNonMatching = (@($allFiles).Count - $items.Count)
        Items              = $items
    }
}
