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
    Leaf names to leave in place (e.g. a system BIOS like uni-bios_4_0.rom that the core expects at
    the common root). Case-insensitive.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [int] $MaxPerFolder = 1000,

        [string[]] $ExcludeFiles = @(),

        # Shorten ROM filenames that exceed MaxFileNameLength (keeping the extension and
        # uniqueness). FAT32/exFAT allow at most 255 chars per name; the Pocket community
        # recommends shorter names. Off by default.
        [switch] $ShortenNames,

        [int] $MaxFileNameLength = 100
    )

    if ($MaxPerFolder -lt 1) { throw "MaxPerFolder must be at least 1." }
    # Clamp the name cap: never above the FAT/exFAT hard limit (255), never absurdly small.
    $nameCap = [Math]::Max(16, [Math]::Min($MaxFileNameLength, 255))
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

    # Shorten an overlong filename: keep the extension, truncate the base, and append a short
    # deterministic token (from the original name) to keep distinct long names distinct. Names
    # already within the cap are returned unchanged, so re-running is idempotent.
    $shorten = {
        param($name)
        if (-not $ShortenNames -or $name.Length -le $nameCap) { return $name }
        $ext = [System.IO.Path]::GetExtension($name)
        $bn  = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $md5 = [System.Security.Cryptography.MD5]::Create()
        try { $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($name)) } finally { $md5.Dispose() }
        $suffix = '~' + (($hash[0].ToString('x2') + $hash[1].ToString('x2')))   # ~ + 4 hex chars
        $budget = $nameCap - $ext.Length - $suffix.Length
        if ($budget -lt 1) { $budget = 1 }
        if ($bn.Length -gt $budget) { $bn = $bn.Substring(0, $budget) }
        return ($bn + $suffix + $ext)
    }

    # The tool-managed favourites folder (symlinks/copies of favourited ROMs) is not part of
    # the library to re-bucket - skip anything inside it (current "!Favorites" or legacy name).
    $all = @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PocketReservedRomPath -Common $commonFull -FullPath $_.FullName) })
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

        # Shorten an overlong name first, then ensure a unique leaf within the destination
        # folder (recursion can surface two files with the same name from different old
        # subfolders, and shortening can map two long names to the same short stem).
        $leaf = & $shorten $f.Name
        $key = (Join-Path $destDir $leaf).ToLowerInvariant()
        if ($seenDest.ContainsKey($key)) {
            $bn = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
            $ext = [System.IO.Path]::GetExtension($leaf)
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
            Source       = $f.FullName
            Destination  = $dest
            Bucket       = $bucket
            Action       = $action
            SizeBytes    = $f.Length
            OriginalName = $f.Name
            NewName      = $leaf
            Renamed      = ($leaf -ne $f.Name)
        }
    }
    $items = @($items)
    $moves = @($items | Where-Object { $_.Action -ne 'None' })
    $renamed = @($items | Where-Object { $_.Renamed })
    $buckets = @($items | Where-Object { $_.Bucket } | ForEach-Object { $_.Bucket } | Select-Object -Unique)

    [pscustomobject]@{
        PSTypeName        = 'PocketPrep.RomOrganizePlan'
        PlatformId        = $PlatformId
        Common            = $commonFull
        FileCount         = $files.Count
        ExcludedCount     = $excludedCount
        MaxPerFolder      = $MaxPerFolder
        NeedsBuckets      = $needsBuckets
        BucketCount       = $buckets.Count
        Buckets           = @($buckets)
        MoveCount         = $moves.Count
        ShortenNames      = [bool]$ShortenNames
        MaxFileNameLength = $nameCap
        RenamedCount      = $renamed.Count
        Renamed           = @($renamed | ForEach-Object { [pscustomobject]@{ From = $_.OriginalName; To = $_.NewName } })
        Items             = $items
    }
}
