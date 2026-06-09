function Install-PocketImagePack {
<#
.SYNOPSIS
    Installs a platform image pack into Platforms/_images (the openFPGA menu artwork).

.DESCRIPTION
    Downloads a community image pack from its GitHub release (or installs a local .zip) and
    extracts ONLY the platform images into Platforms/_images on the card. Like the core
    installer it is traversal-safe (a malicious zip can't write outside the SD root),
    non-destructive (existing images are skipped unless -Overwrite), space-preflighted, and
    supports -DryRun. It writes nothing outside Platforms/_images.

    The tool bundles no images and picks no default pack - you supply the GitHub owner/repo (or
    a local zip), so the source and its licence are your choice. Any zip entry under an
    "_images/" folder is mapped to Platforms/_images/<rest>.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER Owner
    GitHub owner of the image-pack repo (download mode).

.PARAMETER Repo
    GitHub repository name (download mode).

.PARAMETER Tag
    Specific release tag; defaults to the latest release.

.PARAMETER LocalZip
    Path to an image-pack .zip you already downloaded (offline mode).

.PARAMETER Overwrite
    Overwrite images that already exist.

.PARAMETER DryRun
    Plan only; download/extract nothing.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [CmdletBinding(DefaultParameterSetName = 'Download')]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory, ParameterSetName = 'Download')]
        [string] $Owner,

        [Parameter(Mandatory, ParameterSetName = 'Download')]
        [string] $Repo,

        [Parameter(ParameterSetName = 'Download')]
        [string] $Tag,

        [Parameter(Mandatory, ParameterSetName = 'Offline')]
        [string] $LocalZip,

        [switch] $Overwrite,
        [switch] $DryRun,
        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }
    $marker = '_images/'

    $zipPath = $null; $cleanup = $false; $tmpDir = $null; $version = $null
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Download') {
            $rel = Get-PocketLatestRelease -Owner $Owner -Repo $Repo -Tag $Tag
            $version = $rel.Version
            if (-not $rel.ZipUrl) { throw "No .zip asset found in release '$version' for $Owner/$Repo." }
            if ($DryRun) {
                & $log "DRYRUN image pack: would download $($rel.ZipName) ($version) from $Owner/$Repo" 'INFO'
            } else {
                $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("PocketPrepImg_" + [System.IO.Path]::GetRandomFileName())
                New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
                $cleanup = $true
                $zipPath = Join-Path $tmpDir $rel.ZipName
                & $log "Downloading image pack $Owner/$Repo $version" 'INFO'
                $null = Invoke-PocketDownload -Uri $rel.ZipUrl -OutFile $zipPath -MaxBytes 1GB `
                    -OnRetry { param($n, $d, $e) & $log "Image pack download attempt $n failed ($($e.Exception.Message)); retrying in ${d}s" 'WARN' }
            }
        } else {
            if (-not (Test-Path -LiteralPath $LocalZip -PathType Leaf)) { throw "Local image-pack zip not found: $LocalZip" }
            $zipPath = (Resolve-Path -LiteralPath $LocalZip).Path
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $rootFull   = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
        $imagesRoot = Join-Path $rootFull (Join-Path 'Platforms' '_images')
        $placed  = [System.Collections.Generic.List[string]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()

        # In dry-run download mode we have no zip to inspect; report intent only.
        if ($DryRun -and -not $zipPath) {
            return [pscustomobject]@{ PSTypeName='PocketPrep.ImagePackResult'; Owner=$Owner; Repo=$Repo; Version=$version; PlacedCount=0; SkippedCount=0; DryRun=$true }
        }

        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $imageEntries = @($zip.Entries | Where-Object {
                $r = ($_.FullName -replace '\\', '/')
                (-not $r.EndsWith('/')) -and ($r.ToLowerInvariant().Contains($marker))
            })
            if ($imageEntries.Count -eq 0) { throw "Zip contains no platform images (no '_images/' entries)." }

            if (-not $DryRun) {
                $payload = [int64]((@($imageEntries) | Measure-Object -Property Length -Sum).Sum)
                Assert-PocketFreeSpace -Root $rootFull -RequiredBytes $payload -Label "image pack"
            }

            foreach ($entry in $imageEntries) {
                $r = ($entry.FullName -replace '\\', '/')
                $idx = $r.ToLowerInvariant().IndexOf($marker)
                $sub = $r.Substring($idx + $marker.Length)
                if ([string]::IsNullOrEmpty($sub)) { continue }
                $dest = [System.IO.Path]::GetFullPath((Join-Path $imagesRoot $sub))
                if (-not $dest.StartsWith($imagesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Refusing to extract entry outside Platforms/_images: $r"
                }
                if ($DryRun) { $placed.Add($sub); continue }
                if ((Test-Path -LiteralPath $dest) -and -not $Overwrite) { $skipped.Add($sub); continue }
                $destDir = Split-Path -Parent $dest
                if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
                $placed.Add($sub)
            }
        } finally { $zip.Dispose() }

        & $log "Image pack: placed $($placed.Count), skipped $($skipped.Count)$(if ($DryRun) { ' [dry-run]' })" 'INFO'
        [pscustomobject]@{
            PSTypeName  = 'PocketPrep.ImagePackResult'
            Owner       = $Owner; Repo = $Repo; Version = $version
            PlacedCount = $placed.Count
            SkippedCount = $skipped.Count
            DryRun      = [bool]$DryRun
        }
    } finally {
        if ($cleanup -and $tmpDir -and (Test-Path -LiteralPath $tmpDir)) {
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
