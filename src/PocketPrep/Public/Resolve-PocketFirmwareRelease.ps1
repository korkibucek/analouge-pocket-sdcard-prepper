function Resolve-PocketFirmwareRelease {
<#
.SYNOPSIS
    Selects a firmware release from a manifest (latest by default).

.PARAMETER Manifest
    A manifest object from Get-PocketFirmwareManifest.

.PARAMETER Version
    Specific version to select. Defaults to the manifest's 'latest'.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [psobject] $Manifest,

        [string] $Version
    )

    if (-not $Version) { $Version = $Manifest.latest }

    $release = $Manifest.releases | Where-Object { $_.version -eq $Version } | Select-Object -First 1
    if (-not $release) {
        $available = ($Manifest.releases.version) -join ', '
        throw "Firmware version '$Version' not found in manifest. Available: $available"
    }
    return $release
}
