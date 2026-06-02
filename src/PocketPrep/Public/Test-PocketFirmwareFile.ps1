function Test-PocketFirmwareFile {
<#
.SYNOPSIS
    Validates a firmware .bin file against an expected MD5 and (optionally) size.

.DESCRIPTION
    Pure, offline validation used by both the download path and the manual/offline
    path. Returns a verdict object; the caller decides whether to proceed.

.PARAMETER Path
    Path to the firmware file to validate.

.PARAMETER ExpectedMd5
    Expected lowercase/uppercase MD5 hex digest (case-insensitive).

.PARAMETER ExpectedSizeBytes
    Optional expected size in bytes.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $ExpectedMd5,

        [int64] $ExpectedSizeBytes
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Firmware file not found: $Path"
    }

    $actualMd5  = Get-PocketMd5 -Path $Path
    $actualSize = (Get-Item -LiteralPath $Path).Length

    $md5Ok  = ($actualMd5 -ieq $ExpectedMd5.Trim())
    $sizeOk = $true
    if ($PSBoundParameters.ContainsKey('ExpectedSizeBytes') -and $ExpectedSizeBytes -gt 0) {
        $sizeOk = ($actualSize -eq $ExpectedSizeBytes)
    }

    $reasons = [System.Collections.Generic.List[string]]::new()
    if (-not $md5Ok)  { $reasons.Add("MD5 mismatch: expected $($ExpectedMd5.ToLowerInvariant()), got $actualMd5.") }
    if (-not $sizeOk) { $reasons.Add("Size mismatch: expected $ExpectedSizeBytes bytes, got $actualSize.") }

    [pscustomobject]@{
        PSTypeName  = 'PocketPrep.FirmwareVerdict'
        Path        = $Path
        Valid       = ($md5Ok -and $sizeOk)
        ActualMd5   = $actualMd5
        ExpectedMd5 = $ExpectedMd5.ToLowerInvariant()
        ActualSize  = $actualSize
        Reasons     = $reasons.ToArray()
    }
}
