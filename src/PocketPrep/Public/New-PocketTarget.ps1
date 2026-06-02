function New-PocketTarget {
<#
.SYNOPSIS
    Creates a target descriptor for an SD card root or a fake SD root (test mode).

.DESCRIPTION
    Centralises the "where are we writing?" decision so the same logic runs against
    a real card (e.g. E:\) or an ordinary folder (e.g. C:\Temp\PocketSDTest) without
    any code changes. In test mode the folder is created if missing; for a real
    drive the root must already exist.

.PARAMETER Root
    The SD root path or fake SD root folder.

.PARAMETER TestMode
    Treat Root as a normal folder for safe local testing (creates it if needed).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [switch] $TestMode
    )

    if ($TestMode) {
        if (-not (Test-Path -LiteralPath $Root)) {
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Target root not found: $Root. (Use -TestMode to auto-create a fake SD root folder.)"
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.Target'
        Root       = (Resolve-Path -LiteralPath $Root).Path
        IsTestMode = [bool]$TestMode
    }
}
