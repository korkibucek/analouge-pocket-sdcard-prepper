function Save-PocketRomRecipe {
<#
.SYNOPSIS
    Fetches an arcade core's rom-recipes release asset to a working folder on the card.

.DESCRIPTION
    Arcade cores ship their build recipes (.mra/.xml descriptions of how to assemble each
    game's instance .json + .rom from a MAME romset) as a SECOND release asset (e.g.
    boogermann.gberet_rom-recipes-0.1.1.zip). This downloads that asset from the core's
    GitHub release and extracts it to pocketprep/rom-recipes/<coreId>/ so the user has the
    recipes at hand for an openFPGA arcade packager tool.

    Recipes are metadata published by the core author - this fetches NO game ROMs and never
    will; the user combines the recipes with a MAME set they own, outside this tool.
    Extraction is confined to the destination folder (zip-slip safe). Supports -DryRun.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER CoreId
    The arcade core's catalog id (manifests/cores.json).

.PARAMETER CoresManifest
    Path to manifests/cores.json.

.PARAMETER DryRun
    Plan only; download/extract nothing.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Writes only recipe metadata into a tool-managed working folder; -DryRun previews.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $CoreId,

        [Parameter(Mandatory, Position = 2)]
        [string] $CoresManifest,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    $core = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest) -Id $CoreId
    if (-not $core) { throw "Core id '$CoreId' not found in the manifest." }

    $rel = Get-PocketLatestRelease -Owner $core.Owner -Repo $core.Repo -AssetPattern 'rom[-_]?recipes'
    if (-not $rel.ZipUrl) {
        throw "No rom-recipes asset found in the latest release of $($core.Owner)/$($core.Repo). This core may not publish recipes (check its homepage: $($core.Homepage))."
    }

    $destDir = Join-Path (Join-Path (Join-Path $Root 'pocketprep') 'rom-recipes') $CoreId
    if ($DryRun) {
        & $log "DRYRUN recipes: would download $($rel.ZipName) to $destDir" 'INFO'
        return [pscustomobject]@{ PSTypeName='PocketPrep.RomRecipesResult'; CoreId=$CoreId; Version=$rel.Version; Destination=$destDir; PlacedCount=0; DryRun=$true }
    }

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("PocketPrepRcp_" + [System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    try {
        $zipPath = Join-Path $tmpDir $rel.ZipName
        & $log "Downloading rom-recipes $($rel.ZipName) ($($rel.Version))" 'INFO'
        $null = Invoke-PocketDownload -Uri $rel.ZipUrl -OutFile $zipPath -MaxBytes 200MB `
            -OnRetry { param($n, $d, $e) & $log "Recipes download attempt $n failed ($($e.Exception.Message)); retrying in ${d}s" 'WARN' }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        $destFull = (Resolve-Path -LiteralPath $destDir).Path.TrimEnd('\', '/')
        $placed = 0
        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            foreach ($entry in $zip.Entries) {
                $relPath = $entry.FullName -replace '\\', '/'
                if ([string]::IsNullOrEmpty($relPath) -or $relPath.EndsWith('/')) { continue }
                $dest = [System.IO.Path]::GetFullPath((Join-Path $destFull $relPath))
                if (-not $dest.StartsWith($destFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Refusing to extract recipes entry outside the destination: $relPath"
                }
                $dDir = Split-Path -Parent $dest
                if (-not (Test-Path -LiteralPath $dDir)) { New-Item -ItemType Directory -Path $dDir -Force | Out-Null }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
                $placed++
            }
        } finally { $zip.Dispose() }

        & $log "Recipes for ${CoreId}: $placed file(s) -> $destDir" 'INFO'
        [pscustomobject]@{
            PSTypeName  = 'PocketPrep.RomRecipesResult'
            CoreId      = $CoreId
            Version     = $rel.Version
            Destination = $destDir
            PlacedCount = $placed
            DryRun      = $false
        }
    } finally {
        Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
