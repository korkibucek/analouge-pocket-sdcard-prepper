function Get-PocketFavorite {
<#
.SYNOPSIS
    Reads the saved per-platform ROM favourites from a card (or fake SD root).

.DESCRIPTION
    Returns the favourites recorded at pocketprep/favorites.json - a names-only list (never
    any ROM data) of which ROMs are tagged as favourites for each platform. An absent or
    unparseable file yields an empty, valid result with Exists = $false.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    Optionally return only this platform's favourite names (as a string array).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [string] $PlatformId
    )

    $path = Join-Path (Join-Path $Root 'pocketprep') 'favorites.json'
    $platforms = [System.Collections.Generic.List[object]]::new()
    $exists = $false
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try {
            $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $exists = $true
            $fav = $raw.favorites
            if ($fav) {
                foreach ($prop in $fav.PSObject.Properties) {
                    $names = @($prop.Value | Where-Object { $_ } | ForEach-Object { [string]$_ })
                    $platforms.Add([pscustomobject]@{ PlatformId = $prop.Name; Names = $names })
                }
            }
        } catch {
            Write-Warning "Could not parse ${path}: $_ - treating as no favourites."
            $exists = $false
        }
    }

    if ($PlatformId) {
        $hit = $platforms | Where-Object { $_.PlatformId -eq $PlatformId } | Select-Object -First 1
        return @(if ($hit) { $hit.Names } else { @() })
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.Favorites'
        Version    = 1
        Path       = $path
        Exists     = $exists
        Platforms  = $platforms.ToArray()
    }
}
