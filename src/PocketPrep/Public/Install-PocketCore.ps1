function Install-PocketCore {
<#
.SYNOPSIS
    Installs an openFPGA core onto the SD root from a local zip (offline) or by
    downloading the core's GitHub release (download mode).

.DESCRIPTION
    Extracts only the recognised openFPGA top-level folders (Assets, Cores, Platforms,
    Presets, Settings) from the core zip onto the card, merging with what's already
    there. It is non-destructive: existing files are skipped unless -Overwrite. Every
    entry is path-checked so a malicious zip cannot write outside the SD root
    (zip-slip protection). Supports -DryRun.

    This tool does not bundle cores or relicense them; cores remain under their
    authors' licences. BIOS files are never installed here.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER LocalZip
    Path to a core .zip you already downloaded (offline mode).

.PARAMETER Core
    A core object from Resolve-PocketCore. Required for download mode; optional in
    offline mode to validate the expected core folder.

.PARAMETER Tag
    Specific GitHub release tag to download. Defaults to the latest release.

.PARAMETER Overwrite
    Overwrite files that already exist on the card.

.PARAMETER DryRun
    Plan only; do not download or extract.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Download',
        Justification = 'Switch selects the Download parameter set; not referenced directly in the body.')]
    [CmdletBinding(DefaultParameterSetName = 'Offline')]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory, ParameterSetName = 'Offline')]
        [string] $LocalZip,

        [Parameter(ParameterSetName = 'Offline')]
        [Parameter(Mandatory, ParameterSetName = 'Download')]
        [psobject] $Core,

        [Parameter(Mandatory, ParameterSetName = 'Download')]
        [switch] $Download,

        [Parameter(ParameterSetName = 'Download')]
        [string] $Tag,

        [switch] $Overwrite,
        [switch] $DryRun,
        [psobject] $Logger
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "SD root path not found or not a folder: $Root"
    }
    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    $allowedTop = @('Assets', 'Cores', 'Platforms', 'Presets', 'Settings')

    $zipPath = $null
    $cleanup = $false
    $resolvedVersion = $null
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Download') {
            & $log "Resolving core release for $($Core.Owner)/$($Core.Repo)" 'INFO'
            $rel = Get-PocketLatestRelease -Owner $Core.Owner -Repo $Core.Repo -Tag $Tag
            $resolvedVersion = $rel.Version
            if (-not $rel.ZipUrl) { throw "No .zip asset found in release '$resolvedVersion' for $($Core.Owner)/$($Core.Repo)." }
            $assetUrl  = $rel.ZipUrl
            $assetName = $rel.ZipName

            if ($DryRun) {
                & $log "DRYRUN core: would download $assetName ($resolvedVersion) and install to $Root" 'INFO'
                return [pscustomobject]@{
                    PSTypeName = 'PocketPrep.CoreResult'; Mode = 'Download'
                    CoreId = $Core.Id; Identifier = $Core.Identifier; Version = $resolvedVersion
                    PlacedCount = 0; SkippedCount = 0; DryRun = $true; Warnings = @()
                }
            }
            $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("PocketPrepCore_" + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
            $cleanup = $true
            $zipPath = Join-Path $tmpDir $assetName
            & $log "Downloading core $($Core.Identifier) $resolvedVersion" 'INFO'
            $null = Invoke-PocketDownload -Uri $assetUrl -OutFile $zipPath -MaxBytes 1GB `
                -OnRetry { param($n, $d, $e) & $log "Core download attempt $n failed ($($e.Exception.Message)); retrying in ${d}s" 'WARN' }
        } else {
            if (-not (Test-Path -LiteralPath $LocalZip -PathType Leaf)) {
                throw "Local core zip not found: $LocalZip"
            }
            $zipPath = (Resolve-Path -LiteralPath $LocalZip).Path
        }

        # Validate the zip structure (and traversal safety) before touching the card.
        $verdict = if ($Core) {
            Test-PocketCoreZip -Path $zipPath -ExpectedIdentifier $Core.Identifier
        } else {
            Test-PocketCoreZip -Path $zipPath
        }
        if ($verdict.UnsafeEntries.Count -gt 0) {
            throw "Core zip contains unsafe paths (possible zip-slip); refusing to extract: $($verdict.UnsafeEntries -join ', ')"
        }
        if (-not $verdict.HasStructure) {
            throw "Zip does not look like an openFPGA core (no Assets/Cores/Platforms folder)."
        }
        if ($Core -and -not $verdict.HasExpectedCore) {
            throw "Zip does not contain the expected core folder Cores/$($Core.Identifier)/."
        }

        if ($DryRun) {
            & $log "DRYRUN core: would install from $zipPath to $Root" 'INFO'
            return [pscustomobject]@{
                PSTypeName = 'PocketPrep.CoreResult'; Mode = $PSCmdlet.ParameterSetName
                CoreId = ($Core.Id); Identifier = ($Core.Identifier); Version = $resolvedVersion
                PlacedCount = 0; SkippedCount = 0; DryRun = $true; Warnings = @()
            }
        }

        # Extract only recognised top-level folders, non-destructively, traversal-safe.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $rootFull = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
        $placed  = [System.Collections.Generic.List[string]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()

        $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            # Preflight: ensure the card has room for the extracted (uncompressed) payload.
            $payloadBytes = [int64](($zip.Entries |
                Where-Object { $allowedTop -contains (($_.FullName -replace '\\', '/') -split '/')[0] } |
                Measure-Object -Property Length -Sum).Sum)
            Assert-PocketFreeSpace -Root $rootFull -RequiredBytes $payloadBytes -Label "core $($Core.Identifier)"

            foreach ($entry in $zip.Entries) {
                $rel = $entry.FullName -replace '\\', '/'
                if ([string]::IsNullOrEmpty($rel)) { continue }
                $top = ($rel -split '/')[0]
                if ($allowedTop -notcontains $top) { continue }
                if ($rel.EndsWith('/')) { continue }   # directory entry

                $dest = [System.IO.Path]::GetFullPath((Join-Path $rootFull $rel))
                if (-not $dest.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Refusing to extract entry outside SD root: $rel"
                }

                if ((Test-Path -LiteralPath $dest) -and -not $Overwrite) {
                    $skipped.Add($rel)
                    continue
                }
                $destDir = Split-Path -Parent $dest
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
                $placed.Add($rel)
            }
        } finally {
            $zip.Dispose()
        }

        & $log "Core installed: placed $($placed.Count), skipped $($skipped.Count)" 'INFO'
        [pscustomobject]@{
            PSTypeName  = 'PocketPrep.CoreResult'
            Mode        = $PSCmdlet.ParameterSetName
            CoreId      = ($Core.Id)
            Identifier  = ($Core.Identifier)
            Version     = $resolvedVersion
            PlacedCount = $placed.Count
            SkippedCount= $skipped.Count
            DryRun      = $false
            Warnings    = @()
        }
    } finally {
        if ($cleanup -and $tmpDir -and (Test-Path -LiteralPath $tmpDir)) {
            Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
