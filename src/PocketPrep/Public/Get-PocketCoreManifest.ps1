function Get-PocketCoreManifest {
<#
.SYNOPSIS
    Loads and validates the cores manifest (manifests/cores.json).

.DESCRIPTION
    openFPGA cores are made by independent authors. This manifest stores the GitHub
    repository coordinates (owner/repo) and core identifier so the tool can resolve a
    release zip at install time, or link the user to the homepage for a manual
    download. Brittle per-release asset URLs are deliberately NOT stored.

.PARAMETER Path
    Path to the cores manifest JSON file.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Cores manifest not found: $Path"
    }
    try {
        $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Cores manifest '$Path' is not valid JSON: $_"
    }
    if (-not $json.cores -or @($json.cores).Count -eq 0) {
        throw "Cores manifest '$Path' has no 'cores'."
    }

    $seen = @{}
    foreach ($c in $json.cores) {
        # platformIds may legitimately be empty (cores with no ROM platform); only require
        # the property to exist, not to be non-empty.
        foreach ($field in 'id', 'identifier', 'displayName', 'owner', 'repo') {
            if (-not $c.PSObject.Properties[$field] -or -not $c.$field) {
                throw "Cores manifest '$Path' has an entry missing required field '$field'."
            }
        }
        if (-not $c.PSObject.Properties['platformIds']) {
            throw "Cores manifest '$Path' entry '$($c.id)' is missing 'platformIds'."
        }
        if ($seen.ContainsKey($c.id)) {
            throw "Cores manifest '$Path' has duplicate core id '$($c.id)'."
        }
        $seen[$c.id] = $true
    }

    return $json
}
