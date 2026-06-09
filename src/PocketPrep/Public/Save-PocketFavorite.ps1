function Save-PocketFavorite {
<#
.SYNOPSIS
    Sets the favourite ROM list for one platform and writes pocketprep/favorites.json.

.DESCRIPTION
    Replaces the favourites recorded for the given platform with Names (de-duplicated,
    trimmed). Pass an empty Names to clear a platform's favourites. The file holds only ROM
    file names per platform - never any ROM data. Use Sync-PocketFavorite afterwards to
    materialise the Favorites folder.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform whose favourites to set.

.PARAMETER Names
    The ROM file names (leaf names) to mark as favourites for this platform.

.PARAMETER DryRun
    Validate and report without writing the file.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Non-destructive single-file write; -DryRun provides the preview path.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [Parameter(Mandatory, Position = 2)]
        [AllowEmptyCollection()]
        [string[]] $Names,

        [switch] $DryRun
    )

    if ([string]::IsNullOrWhiteSpace($PlatformId)) { throw "PlatformId is required." }

    # Start from the existing favourites so other platforms are preserved.
    $existing = Get-PocketFavorite -Root $Root
    $map = [ordered]@{}
    foreach ($p in @($existing.Platforms)) { $map[$p.PlatformId] = @($p.Names) }

    # De-dupe (case-insensitive) and trim the leaf names for this platform.
    $seen = @{}; $clean = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $Names) {
        $leaf = ([string]$n).Trim()
        if (-not $leaf) { continue }
        $key = $leaf.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true; $clean.Add($leaf)
    }

    if ($clean.Count -gt 0) { $map[$PlatformId] = $clean.ToArray() }
    elseif ($map.Contains($PlatformId)) { $map.Remove($PlatformId) }

    $dir  = Join-Path $Root 'pocketprep'
    $path = Join-Path $dir 'favorites.json'
    $config = [ordered]@{ version = 1; favorites = $map }

    if (-not $DryRun) {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.FavoritesSaveResult'
        Path       = $path
        PlatformId = $PlatformId
        Count      = $clean.Count
        DryRun     = [bool]$DryRun
        Written    = (-not $DryRun)
    }
}
