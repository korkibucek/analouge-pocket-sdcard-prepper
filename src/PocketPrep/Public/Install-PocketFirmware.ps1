function Install-PocketFirmware {
<#
.SYNOPSIS
    Places Analogue Pocket firmware at the SD root, by official download or from a
    user-supplied local file (offline mode).

.DESCRIPTION
    The Pocket expects a single firmware .bin at the root of the card (source:
    Analogue "Updating Firmware" guide). This function:

      * Download mode (-Release): downloads from the official analogue.co URL in the
        manifest, verifies MD5 (and size) BEFORE placing the file, and refuses to
        install on mismatch. Non-analogue.co hosts are rejected.
      * Offline mode (-LocalFile): copies a firmware file the user already has. If
        -ExpectedMd5 is supplied (or available via -Release), it is verified too.

    It never deletes existing files. If other .bin files are present at the root it
    warns (the Pocket wants exactly one firmware file) but leaves them in place.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER Release
    A firmware release object from Resolve-PocketFirmwareRelease (download mode, or
    to supply expected checksum/filename for offline mode).

.PARAMETER LocalFile
    Path to an already-downloaded firmware .bin (offline mode).

.PARAMETER DownloadDirectory
    Where to stage the download before validation. Defaults to a temp folder.

.PARAMETER DryRun
    Plan only; do not download or copy.

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
        [psobject] $Release,

        [Parameter(Mandatory, ParameterSetName = 'Offline')]
        [string] $LocalFile,

        [Parameter(ParameterSetName = 'Offline')]
        [psobject] $OfflineRelease,

        [Parameter(ParameterSetName = 'Offline')]
        [string] $ExpectedMd5,

        [string] $DownloadDirectory,

        [switch] $DryRun,

        [psobject] $Logger
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "SD root path not found or not a folder: $Root"
    }

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    $warnings = [System.Collections.Generic.List[string]]::new()

    # Determine the destination filename and (if known) expected checksum/version.
    if ($PSCmdlet.ParameterSetName -eq 'Download') {
        $fileName    = $Release.fileName
        $version     = $Release.version
        $expectedMd5 = $Release.md5
        $expectedSz  = [int64]$Release.sizeBytes
        $url         = $Release.url
    } else {
        $effectiveRelease = $OfflineRelease
        $fileName    = if ($effectiveRelease) { $effectiveRelease.fileName } else { Split-Path -Leaf $LocalFile }
        $version     = if ($effectiveRelease) { $effectiveRelease.version } else { 'unknown' }
        $expectedMd5 = if ($ExpectedMd5) { $ExpectedMd5 } elseif ($effectiveRelease) { $effectiveRelease.md5 } else { $null }
        $expectedSz  = if ($effectiveRelease) { [int64]$effectiveRelease.sizeBytes } else { 0 }
    }

    $destination = Join-Path $Root $fileName

    # Warn about other firmware files already on the card (do not delete them).
    $otherBin = Get-ChildItem -LiteralPath $Root -Filter '*.bin' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $fileName }
    foreach ($b in $otherBin) {
        $warnings.Add("Another firmware-like file is present at the root: $($b.Name). The Pocket expects only one firmware file - remove it manually before updating.")
    }

    if ($DryRun) {
        & $log "DRYRUN firmware: would install $fileName (v$version) to $destination" 'INFO'
        return [pscustomobject]@{
            PSTypeName  = 'PocketPrep.FirmwareResult'
            Mode        = $PSCmdlet.ParameterSetName
            Version     = $version
            FileName    = $fileName
            Destination = $destination
            Md5Verified = $false
            OnCardVerified = $false
            DryRun      = $true
            Warnings    = $warnings.ToArray()
        }
    }

    # Obtain the source file (download or local), validate, then place it.
    $sourceFile = $null
    $cleanupTemp = $false
    try {
        if ($PSCmdlet.ParameterSetName -eq 'Download') {
            $urlHost = ([Uri]$url).Host
            if ($script:PocketDefaults.AllowedFirmwareHosts -notcontains $urlHost) {
                throw "Refusing to download firmware from non-official host '$urlHost'. Only analogue.co sources are allowed."
            }
            if (-not $DownloadDirectory) {
                $DownloadDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("PocketPrepFw_" + [System.IO.Path]::GetRandomFileName())
            }
            New-Item -ItemType Directory -Path $DownloadDirectory -Force | Out-Null
            $cleanupTemp = $true
            $sourceFile = Join-Path $DownloadDirectory $fileName

            & $log "Downloading firmware v$version from $url" 'INFO'
            $null = Invoke-PocketDownload -Uri $url -OutFile $sourceFile -ExpectedBytes $expectedSz `
                -OnRetry { param($n, $d, $e) & $log "Firmware download attempt $n failed ($($e.Exception.Message)); retrying in ${d}s" 'WARN' }
        } else {
            if (-not (Test-Path -LiteralPath $LocalFile -PathType Leaf)) {
                throw "Local firmware file not found: $LocalFile"
            }
            $sourceFile = $LocalFile
        }

        $md5Verified = $false
        if ($expectedMd5) {
            $verdict = Test-PocketFirmwareFile -Path $sourceFile -ExpectedMd5 $expectedMd5 -ExpectedSizeBytes $expectedSz
            if (-not $verdict.Valid) {
                throw "Firmware validation failed: $($verdict.Reasons -join ' ') Refusing to install."
            }
            $md5Verified = $true
            & $log "Firmware MD5 verified: $($verdict.ActualMd5)" 'INFO'
        } else {
            $warnings.Add('No expected MD5 was available, so the firmware file could not be checksum-verified.')
            & $log 'No expected MD5 available; firmware not checksum-verified.' 'WARN'
        }

        # Preflight: ensure the card has room for the firmware before placing it.
        $fwBytes = (Get-Item -LiteralPath $sourceFile).Length
        Assert-PocketFreeSpace -Root $Root -RequiredBytes $fwBytes -Label "firmware v$version"

        Copy-Item -LiteralPath $sourceFile -Destination $destination -Force
        & $log "Firmware placed at $destination" 'INFO'

        # Post-write verification: re-hash the file as it now sits ON THE CARD, so a
        # truncated/corrupted copy (or a card pulled mid-write) is caught, not reported
        # as success.
        $onCardVerified = $false
        if ($expectedMd5) {
            $after = Test-PocketFirmwareFile -Path $destination -ExpectedMd5 $expectedMd5 -ExpectedSizeBytes $expectedSz
            if (-not $after.Valid) {
                throw "Firmware on the card failed verification after writing ($($after.Reasons -join ' ')). The card copy is corrupt - do not use it; re-run the install."
            }
            $onCardVerified = $true
            & $log "Firmware verified on card: $($after.ActualMd5)" 'INFO'
        }

        [pscustomobject]@{
            PSTypeName     = 'PocketPrep.FirmwareResult'
            Mode           = $PSCmdlet.ParameterSetName
            Version        = $version
            FileName       = $fileName
            Destination    = $destination
            Md5Verified    = $md5Verified
            OnCardVerified = $onCardVerified
            DryRun         = $false
            Warnings       = $warnings.ToArray()
        }
    } finally {
        if ($cleanupTemp -and $sourceFile -and (Test-Path -LiteralPath $sourceFile)) {
            Remove-Item -LiteralPath $sourceFile -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $DownloadDirectory -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}
