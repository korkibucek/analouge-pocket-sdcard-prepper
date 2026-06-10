function Resolve-PocketCore {
<#
.SYNOPSIS
    Returns one core (by id) or all cores from a cores manifest, as normalised objects.

.PARAMETER Manifest
    A manifest object from Get-PocketCoreManifest.

.PARAMETER Id
    Optional core id to select a single entry.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [psobject] $Manifest,

        [string] $Id
    )

    $cores = foreach ($c in $Manifest.cores) {
        [pscustomobject]@{
            PSTypeName   = 'PocketPrep.Core'
            Id           = $c.id
            Identifier   = $c.identifier
            DisplayName  = $c.displayName
            PlatformIds  = @($c.platformIds)
            Owner        = $c.owner
            Repo         = $c.repo
            Tag          = [string]$c.tag
            Sha256       = [string]$c.sha256
            AssetPattern = [string]$c.assetPattern
            Homepage     = [string]$c.homepage
            BiosRequired = [bool]$c.biosRequired
            BiosFiles    = @($c.biosFiles)
            Notes        = [string]$c.notes
        }
    }

    if ($Id) {
        $match = $cores | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
        if (-not $match) { throw "Core id '$Id' not found in manifest." }
        return $match
    }
    return @($cores)
}
