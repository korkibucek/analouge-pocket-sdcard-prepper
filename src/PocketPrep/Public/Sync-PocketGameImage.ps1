function Sync-PocketGameImage {
<#
.SYNOPSIS
    Scrapes box art for the games actually on the card (never whole image sets).

.DESCRIPTION
    Fetches per-game box art from the community libretro-thumbnails collection on GitHub,
    matched by the ROM's own filename (No-Intro naming), and caches it on the card under
    pocketprep/images/<platformId>/<rom-basename>.png so the app can display it. Fully
    automated - the user never supplies images.

    To match reliably without hammering the source, the repo's file index is fetched ONCE
    (git trees API) and cached (.index.json); each game is then matched exact-first, then
    case-insensitively, then by base title with region/version tags stripped. Only games
    present on the card are fetched - whole sets are never mirrored - and a per-run cap
    (-MaxNew) bounds each run. Downloads come only from raw.githubusercontent.com.
    Set GITHUB_TOKEN to raise the GitHub API rate limit for the index fetch.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform to fetch art for.

.PARAMETER ImageSources
    Path to manifests/image-sources.json (platformId -> libretro-thumbnails repo).

.PARAMETER MaxNew
    Maximum new images to download this run (default 200). Re-run to continue.

.PARAMETER RefreshIndex
    Re-fetch the cached repository index.

.PARAMETER DryRun
    Match and report without downloading.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Writes only image files into a tool-managed cache folder; -DryRun previews.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [Parameter(Mandatory, Position = 2)]
        [string] $ImageSources,

        [int] $MaxNew = 200,

        [switch] $RefreshIndex,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    if (-not (Test-Path -LiteralPath $ImageSources -PathType Leaf)) { throw "Image sources manifest not found: $ImageSources" }
    $map = (Get-Content -LiteralPath $ImageSources -Raw | ConvertFrom-Json).platforms
    $repo = $map.$PlatformId
    if (-not $repo) {
        return [pscustomobject]@{ PSTypeName='PocketPrep.GameImageSync'; PlatformId=$PlatformId; Supported=$false
            Games=0; AlreadyCached=0; Fetched=0; MissingCount=0; Remaining=0; DryRun=[bool]$DryRun }
    }

    $imgDir = Join-Path (Join-Path (Join-Path $Root 'pocketprep') 'images') $PlatformId
    $indexFile = Join-Path $imgDir '.index.json'

    # 1. Repo file index (one API call, cached). Enables case-insensitive + fallback matching.
    $index = $null
    if (-not $RefreshIndex -and (Test-Path -LiteralPath $indexFile -PathType Leaf)) {
        try { $index = Get-Content -LiteralPath $indexFile -Raw | ConvertFrom-Json } catch { $index = $null }
    }
    if (-not $index) {
        $headers = @{ 'User-Agent' = 'PocketPrep' }
        if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
        & $log "Fetching image index for $repo" 'INFO'
        $tree = Invoke-PocketRest -Uri "https://api.github.com/repos/libretro-thumbnails/$repo/git/trees/master?recursive=1" -Headers $headers
        $index = @($tree.tree | ForEach-Object { $_.path } |
            Where-Object { $_ -like 'Named_Boxarts/*.png' } |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension(($_ -replace '^Named_Boxarts/', '')) })
        if (-not $DryRun) {
            if (-not (Test-Path -LiteralPath $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }
            $index | ConvertTo-Json -Compress | Set-Content -LiteralPath $indexFile -Encoding utf8
        }
    }
    $index = @($index)

    # Lookups: exact (lowercased) and base-title (parenthesised tags stripped).
    $sanitize = { param($n) ($n -replace '[&\*/:`<>\?\\\|]', '_') }
    $stripTags = { param($n) ((($n -replace '\([^)]*\)', '') -replace '\[[^\]]*\]', '') -replace '\s+', ' ').Trim().ToLowerInvariant() }
    $exactLookup = @{}; $baseLookup = @{}
    foreach ($name in $index) {
        $k = $name.ToLowerInvariant()
        if (-not $exactLookup.ContainsKey($k)) { $exactLookup[$k] = $name }
        $b = & $stripTags $name
        if ($b -and -not $baseLookup.ContainsKey($b)) { $baseLookup[$b] = $name }
    }

    # 2. Games on the card (reserved tool folders excluded).
    $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'
    $games = @()
    if (Test-Path -LiteralPath $common -PathType Container) {
        $commonFull = (Resolve-Path -LiteralPath $common).Path
        $games = @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-PocketReservedRomPath -Common $commonFull -FullPath $_.FullName) } |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } | Select-Object -Unique)
    }

    # 3. Match + fetch (capped), skipping already-cached images.
    $cached = 0; $fetched = 0; $remaining = 0
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($game in $games) {
        $dest = Join-Path $imgDir "$game.png"
        if (Test-Path -LiteralPath $dest -PathType Leaf) { $cached++; continue }
        $san = (& $sanitize $game)
        $hit = $exactLookup[$san.ToLowerInvariant()]
        if (-not $hit) { $hit = $baseLookup[(& $stripTags $san)] }
        if (-not $hit) { $missing.Add($game); continue }
        if ($fetched -ge $MaxNew) { $remaining++; continue }
        if ($DryRun) { $fetched++; continue }
        try {
            if (-not (Test-Path -LiteralPath $imgDir)) { New-Item -ItemType Directory -Path $imgDir -Force | Out-Null }
            $url = "https://raw.githubusercontent.com/libretro-thumbnails/$repo/master/Named_Boxarts/$([Uri]::EscapeDataString($hit)).png"
            $null = Invoke-PocketDownload -Uri $url -OutFile $dest -MaxBytes 10MB
            $fetched++
        } catch {
            & $log "Image fetch failed for '$game' ($hit): $($_.Exception.Message)" 'WARN'
            $missing.Add($game)
        }
    }

    & $log "Images [$PlatformId]: games=$($games.Count) cached=$cached fetched=$fetched missing=$($missing.Count) remaining=$remaining" 'INFO'
    [pscustomobject]@{
        PSTypeName    = 'PocketPrep.GameImageSync'
        PlatformId    = $PlatformId
        Supported     = $true
        Games         = $games.Count
        AlreadyCached = $cached
        Fetched       = $fetched
        MissingCount  = $missing.Count
        Missing       = $missing.ToArray()
        Remaining     = $remaining
        DryRun        = [bool]$DryRun
    }
}
