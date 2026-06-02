function Get-PocketSystem {
<#
.SYNOPSIS
    Loads and validates the system manifest (manifests/systems.json).

.DESCRIPTION
    Systems are data-driven so they can be added or edited without touching code.
    Each returned object describes one system: id, displayName, manufacturer,
    platformId, supportedExtensions, requiresCore, suggestedCore, biosRequired,
    biosFiles, notes, plus a computed RomDestinationRelative (Assets/<platformId>/common).

.PARAMETER Path
    Path to the systems manifest JSON file.

.PARAMETER Id
    Optionally return only the system with this id.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [string] $Id
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Systems manifest not found: $Path"
    }

    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Systems manifest '$Path' is not valid JSON: $_"
    }

    if (-not $json.systems -or @($json.systems).Count -eq 0) {
        throw "Systems manifest '$Path' has no 'systems'."
    }

    $seen = @{}
    $systems = foreach ($s in $json.systems) {
        foreach ($field in 'id', 'displayName', 'platformId', 'supportedExtensions') {
            if (-not $s.PSObject.Properties[$field] -or -not $s.$field) {
                throw "Systems manifest '$Path' has an entry missing required field '$field'."
            }
        }
        if ($seen.ContainsKey($s.id)) {
            throw "Systems manifest '$Path' has duplicate system id '$($s.id)'."
        }
        $seen[$s.id] = $true

        $exts = @($s.supportedExtensions | ForEach-Object { $_.ToLowerInvariant() })
        foreach ($e in $exts) {
            if ($e -notmatch '^\.[a-z0-9]+$') {
                throw "Systems manifest '$Path' system '$($s.id)' has invalid extension '$e' (expected like '.gb')."
            }
        }

        [pscustomobject]@{
            PSTypeName             = 'PocketPrep.System'
            Id                     = $s.id
            DisplayName            = $s.displayName
            Manufacturer           = [string]$s.manufacturer
            PlatformId             = $s.platformId
            SupportedExtensions    = $exts
            RequiresCore           = [bool]$s.requiresCore
            SuggestedCore          = [string]$s.suggestedCore
            BiosRequired           = [bool]$s.biosRequired
            BiosFiles              = @($s.biosFiles)
            Notes                  = [string]$s.notes
            RomDestinationRelative = (Join-Path (Join-Path 'Assets' $s.platformId) 'common')
        }
    }

    if ($Id) {
        $match = $systems | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
        if (-not $match) {
            throw "System id '$Id' not found in manifest '$Path'."
        }
        return $match
    }

    return @($systems)
}
