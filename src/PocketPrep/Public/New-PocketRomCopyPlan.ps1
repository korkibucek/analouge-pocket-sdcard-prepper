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

        [switch] $Recurse,

        # Disable content-based de-duplication (by default, byte-identical files among the
        # matched set are detected and copied only once).
        [switch] $NoContentDedupe
    )

    if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
        throw "Source ROM folder not found: $SourceFolder"
    }

    $destRoot = Join-Path (Join-Path (Join-Path $Root 'Assets') $System.PlatformId) 'common'
    $exts = $System.SupportedExtensions
    # A system may declare '*' to mean "match any file" - used for platforms imported from an
    # installed core whose ROM extensions aren't known to the manifest (see #128).
    $matchAll = @($exts) -contains '*'
    # Folder-format systems (#200, e.g. Neo Geo DarkSoft sets): each game is a whole
    # DIRECTORY copied as Assets/<plat>/common/<game>/..., so the plan takes every file
    # inside each immediate sub-folder of the source (extensions don't apply) and keeps
    # the game folder in the destination path. The per-file copy/verify/skip/batching
    # machinery in Invoke-PocketRomCopyPlan is unchanged.
    $folderMode = ([string]$System.RomFormat -eq 'folder')

    $sourceFull = (Resolve-Path -LiteralPath $SourceFolder).Path
    $singleGame = $false
    if ($folderMode) {
        $gameDirs = @(Get-ChildItem -LiteralPath $SourceFolder -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not $_.Name.StartsWith('.') })
        if (-not $gameDirs) {
            # Pointed directly AT one game folder: import the folder itself under its name.
            $gameDirs = @(Get-Item -LiteralPath $sourceFull)
            $singleGame = $true
        }
        $allFiles = @($gameDirs | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -File -Recurse -ErrorAction SilentlyContinue })
        $matched = $allFiles
        # Identical support files across different games are legitimate - never
        # content-dedupe a folder set.
        $NoContentDedupe = $true
    } else {
        $allFiles = Get-ChildItem -LiteralPath $SourceFolder -File -Recurse:$Recurse -ErrorAction SilentlyContinue
        $matched  = if ($matchAll) { $allFiles } else { $allFiles | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } }
    }

    # Characters that are invalid in FAT32/exFAT file names (besides the path separators).
    $invalidFatChars = [char[]]('<', '>', ':', '"', '|', '?', '*') + @(0..31 | ForEach-Object { [char]$_ })
    $seenDest = @{}      # destination name dedupe
    $seenHash = @{}      # content dedupe
    # Content dedupe (on by default) only hashes files whose SIZE matches another matched
    # file, so it's effectively free for libraries with no real duplicates.
    $sizeCounts = @{}
    foreach ($f in $matched) { $sizeCounts[$f.Length] = 1 + ($sizeCounts[$f.Length] ?? 0) }

    $items = foreach ($f in $matched) {
        if ($folderMode) {
            # Keep the game folder: rel is "<game>/<file...>" (the source's own leaf name
            # when it IS the game folder).
            $rel = $f.FullName.Substring($sourceFull.Length).TrimStart([char]'\', [char]'/').Replace('\', '/')
            if ($singleGame) { $rel = (Split-Path -Leaf $sourceFull) + '/' + $rel }
            $dest = Join-Path $destRoot ($rel -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        } elseif ($PreserveStructure -and $Recurse) {
            $rel = $f.FullName.Substring($sourceFull.Length).TrimStart([char]'\', [char]'/')
            $dest = Join-Path $destRoot $rel
        } else {
            $rel = $f.Name
            $dest = Join-Path $destRoot $f.Name
        }

        # 1. Problems that can't go on the card at all.
        $problem = $null; $duplicate = $null
        $leaf = Split-Path -Leaf $dest
        if ($leaf.IndexOfAny($invalidFatChars) -ge 0) {
            $problem = "name contains characters not allowed on FAT/exFAT"
        } elseif ($dest.Length -gt 259) {
            $problem = "destination path is too long (>259 chars)"
        } else {
            $key = $dest.ToLowerInvariant()
            if ($seenDest.ContainsKey($key)) {
                # 2. Same destination name as an earlier file -> duplicate (only one can land).
                $duplicate = "same name as $($seenDest[$key])"
            } elseif ((-not $NoContentDedupe) -and $sizeCounts[$f.Length] -gt 1) {
                # 3. Same bytes as an earlier file (different name) -> duplicate.
                $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                if ($hash -and $seenHash.ContainsKey($hash)) {
                    $duplicate = "identical to $($seenHash[$hash])"
                } else {
                    if ($hash) { $seenHash[$hash] = $f.Name }
                    $seenDest[$key] = $f.Name
                }
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
            Duplicate    = $duplicate
        }
    }
    $items = @($items)
    $problemItems = @($items | Where-Object { $_.Problem })
    $duplicateItems = @($items | Where-Object { $_.Duplicate -and -not $_.Problem })
    $copyableItems = @($items | Where-Object { -not $_.Problem -and -not $_.Duplicate })
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
        RomFormat          = if ($folderMode) { 'folder' } else { 'file' }
        # Folder mode: one entry per game directory (count of distinct first path segments).
        GameCount          = if ($folderMode) { @($copyableItems | ForEach-Object { ($_.RelativePath -split '/')[0] } | Sort-Object -Unique).Count } else { $null }
        Games              = if ($folderMode) { @($copyableItems | ForEach-Object { ($_.RelativePath -split '/')[0] } | Sort-Object -Unique) } else { @() }
        CopyableCount      = $copyableItems.Count
        ProblemCount       = $problemItems.Count
        Problems           = @($problemItems | ForEach-Object { [pscustomobject]@{ Source = $_.Source; RelativePath = $_.RelativePath; Reason = $_.Problem } })
        DuplicateCount     = $duplicateItems.Count
        Duplicates         = @($duplicateItems | ForEach-Object { [pscustomobject]@{ RelativePath = $_.RelativePath; Reason = $_.Duplicate } })
        TotalBytes         = $totalBytes
        DestinationFreeBytes = $freeBytes
        FitsInDestination  = $fits
        SkippedNonMatching = (@($allFiles).Count - $items.Count)
        Items              = $items
    }
}
