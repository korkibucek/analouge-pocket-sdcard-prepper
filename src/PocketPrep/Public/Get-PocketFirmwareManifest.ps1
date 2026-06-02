function Get-PocketFirmwareManifest {
<#
.SYNOPSIS
    Loads and validates the firmware manifest (manifests/firmware.json).

.DESCRIPTION
    Firmware URLs and checksums live in a manifest, not in code, so a new firmware
    release only needs a JSON edit (documented in docs/manifests.md). This loader
    performs lightweight structural validation and fails fast with a clear error.

.PARAMETER Path
    Path to the firmware manifest JSON file.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Firmware manifest not found: $Path"
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Firmware manifest '$Path' is not valid JSON: $_"
    }

    if (-not $json.releases -or @($json.releases).Count -eq 0) {
        throw "Firmware manifest '$Path' has no 'releases'."
    }

    foreach ($r in $json.releases) {
        foreach ($field in 'version', 'releaseDate', 'url', 'fileName', 'md5', 'sizeBytes') {
            if (-not $r.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$r.$field)) {
                throw "Firmware manifest '$Path' release is missing required field '$field'."
            }
        }
        if ($r.md5 -notmatch '^[0-9a-fA-F]{32}$') {
            throw "Firmware manifest '$Path' release $($r.version) has an invalid md5 '$($r.md5)'."
        }
        if ($r.fileName -notmatch '\.bin$') {
            throw "Firmware manifest '$Path' release $($r.version) fileName must end in .bin."
        }
    }

    if (-not $json.latest) {
        throw "Firmware manifest '$Path' is missing 'latest'."
    }
    if (-not (@($json.releases.version) -contains $json.latest)) {
        throw "Firmware manifest '$Path' 'latest' ($($json.latest)) does not match any release version."
    }

    return $json
}
