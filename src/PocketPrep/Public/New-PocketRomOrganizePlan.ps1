function New-PocketRomOrganizePlan {
<#
.SYNOPSIS
    Plans how to reorganize a core's ROMs into capped alphabetical subfolders.

.DESCRIPTION
    Pure planning function (nothing is moved here - call Invoke-PocketRomOrganizePlan).
    Some openFPGA cores won't list more than a certain number of files in one directory
    (the community ceiling is commonly cited around 1300 per folder). To stay under that, a
    large library is split into letter-range subfolders under Assets/<platformId>/common,
    each holding at most MaxPerFolder files. Analogue's developer docs explicitly allow custom
    subdirectories within the Assets folders, so this is a supported layout.

    Files are gathered recursively (so re-running re-buckets a library that's already in
    subfolders), then sorted and chunked. The plan is idempotent: a library already at or
    under the cap targets the common root with no moves.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform whose ROMs to organize (its folder is Assets/<PlatformId>/common).

.PARAMETER MaxPerFolder
    Maximum files per folder before splitting into subfolders. Default 1000 (igir's proven
    safe value; below the ~1300 community ceiling).

.PARAMETER ExcludeFiles
    Leaf names to leave in place (e.g. a system BIOS like neogeo.zip that the core expects at
    the common root). Case-insensitive.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [int] $MaxPerFolder = 1000,

        [string[]] $ExcludeFiles = @()
    )

    if ($MaxPerFolder -lt 1) { throw "MaxPerFolder must be at least 1." }
    $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'
    if (-not (Test-Path -LiteralPath $common -PathType Container)) {
        throw "No ROM folder for platform '$PlatformId' at $common"
    }
    $commonFull = (Resolve-Path -LiteralPath $common).Path
    $exclude = @{}
    foreach ($e in $ExcludeFiles) { if ($e) { $exclude[$e.ToLowerInvariant()] = $true } }

    # First character bucket key: A-Z for letters, '#' for digits/symbols/other.
    $bucketChar = {
        param($name)
        $c = ($name.Trim()).ToUpperInvariant()
        $ch = if ($c.Length -gt 0) { $c[0] } else { '#' }
        if ($ch -ge 'A' -and $ch -le 'Z') { [string]$ch } else { '#' }
    }

    $all = @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue)
    $files = @($all | Where-Object { -not $exclude.ContainsKey($_.Name.ToLowerInvariant()) } |
        Sort-Object { $_.Name.ToLowerInvariant() })
    $excludedCount = $all.Count - $files.Count

    # Decide buckets. <= cap -> everything at the common root (flatten any existing subfolders).
    $needsBuckets = $files.Count -gt $MaxPerFolder
    $bucketOf = @{}     # index -> bucket label
    if ($needsBuckets) {
        $usedLabels = @{}
        for ($i = 0; $i -lt $files.Count; $i += $MaxPerFolder) {
            $chunk = $files[$i..([Math]::Min($i + $MaxPerFolder - 1, $files.Count - 1))]
            $start = & $bucketChar $chunk[0].Name
            $end   = & $bucketChar $chunk[-1].Name
            $label = if ($start -eq $end) { $start } else { "$start-$end" }
            # Disambiguate if a single letter spans more than one chunk (e.g. 1500 'S' games).
            $base = $label; $n = 2
            while ($usedLabels.ContainsKey($label)) { $label = "$base ($n)"; $n++ }
            $usedLabels[$label] = $true
            for ($j = $i; $j -lt $i + $chunk.Count; $j++) { $bucketOf[$j] = $label }
        }
    }

    $seenDest = @{}     # per target-folder leaf-name uniqueness
    $items = for ($idx = 0; $idx -lt $files.Count; $idx++) {
        $f = $files[$idx]
        $bucket = if ($needsBuckets) { $bucketOf[$idx] } else { '' }
        $destDir = if ($bucket) { Join-Path $commonFull $bucket } else { $commonFull }

        # Ensure a unique leaf within the destination folder (recursion can surface two files
        # with the same name from different old subfolders).
        $leaf = $f.Name
        $key = (Join-Path $destDir $leaf).ToLowerInvariant()
        if ($seenDest.ContainsKey($key)) {
            $bn = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $ext = [System.IO.Path]::GetExtension($f.Name)
            $n = 2
            do { $leaf = "$bn~$n$ext"; $key = (Join-Path $destDir $leaf).ToLowerInvariant(); $n++ }
            while ($seenDest.ContainsKey($key))
        }
        $seenDest[$key] = $true
        $dest = Join-Path $destDir $leaf

        $action = if ($dest -eq $f.FullName) { 'None' }
                  elseif ((Split-Path -Parent $dest) -eq $f.DirectoryName) { 'Rename' }
                  else { 'Move' }

        [pscustomobject]@{
            Source      = $f.FullName
            Destination = $dest
            Bucket      = $bucket
            Action      = $action
            SizeBytes   = $f.Length
        }
    }
    $items = @($items)
    $moves = @($items | Where-Object { $_.Action -ne 'None' })
    $buckets = @($items | Where-Object { $_.Bucket } | ForEach-Object { $_.Bucket } | Select-Object -Unique)

    [pscustomobject]@{
        PSTypeName    = 'PocketPrep.RomOrganizePlan'
        PlatformId    = $PlatformId
        Common        = $commonFull
        FileCount     = $files.Count
        ExcludedCount = $excludedCount
        MaxPerFolder  = $MaxPerFolder
        NeedsBuckets  = $needsBuckets
        BucketCount   = $buckets.Count
        Buckets       = @($buckets)
        MoveCount     = $moves.Count
        Items         = $items
    }
}
