function Export-PocketProfile {
<#
.SYNOPSIS
    Exports a portable setup profile (installed cores + ROM source mapping + favourites).

.DESCRIPTION
    Builds a single JSON-able object describing a card's setup so it can be reproduced on
    another card (Import-PocketProfile): which cores are installed, the saved ROM
    source-folder -> system mapping (pocketprep/rom-sources.json), and the favourites
    (pocketprep/favorites.json). It contains only references (catalog ids, repo coordinates,
    folder paths and file names) - never any ROM or BIOS data.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER CoresManifest
    Optional path to manifests/cores.json, used to map each installed core to its catalog id
    (so Import can reinstall it).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [string] $CoresManifest
    )

    # Map installed core identifiers -> catalog id (where known) so Import can reinstall.
    $idByIdentifier = @{}
    if ($CoresManifest -and (Test-Path -LiteralPath $CoresManifest -PathType Leaf)) {
        try { foreach ($c in @(Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest))) { $idByIdentifier[$c.Identifier.ToLowerInvariant()] = $c.Id } }
        catch { Write-Warning "Could not read cores catalog: $_" }
    }

    $cores = foreach ($ic in @(Get-PocketInstalledCore -Root $Root)) {
        [pscustomobject]@{
            identifier = $ic.Identifier
            id         = $idByIdentifier[$ic.Identifier.ToLowerInvariant()]   # catalog id or $null
            version    = $ic.Version
        }
    }

    $config = Get-PocketRomConfig -Root $Root
    $romSources = foreach ($s in @($config.Sources)) {
        [pscustomobject]@{ systemId = $s.SystemId; path = $s.Path; recurse = [bool]$s.Recurse }
    }

    $fav = Get-PocketFavorite -Root $Root
    $favorites = foreach ($p in @($fav.Platforms)) {
        [pscustomobject]@{ platformId = $p.PlatformId; names = @($p.Names) }
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.Profile'
        version    = 1
        note       = 'PocketPrep setup profile - references only (no ROMs or BIOS).'
        cores      = @($cores)
        romSources = @($romSources)
        favorites  = @($favorites)
    }
}
