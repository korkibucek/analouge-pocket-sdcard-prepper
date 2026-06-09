function Import-PocketProfile {
<#
.SYNOPSIS
    Applies a setup profile to a card: installs its cores, restores ROM config + favourites.

.DESCRIPTION
    Reproduces a setup exported by Export-PocketProfile. It:
      - installs the profile's cores (those with a known catalog id) via Install-PocketCoreSet,
      - restores the saved ROM source mapping (Save-PocketRomConfig),
      - restores the favourites list (Save-PocketFavorite) and syncs each platform,
      - optionally rescans the restored source folders to copy the ROMs (Invoke-PocketRomRescan).
    It copies no ROMs/BIOS itself unless -Rescan is given (which uses the user's own source
    folders). Supports -DryRun.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER ProfileData
    The profile object (parsed JSON) from Export-PocketProfile.

.PARAMETER CoresManifest
    Path to manifests/cores.json (to install the profile's cores).

.PARAMETER SystemsManifest
    Path to manifests/systems.json (needed when -Rescan is used).

.PARAMETER Rescan
    After restoring the source mapping, copy ROMs from those folders to the card.

.PARAMETER DryRun
    Plan only; install/copy nothing and write no files.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [psobject] $ProfileData,

        [string] $CoresManifest,

        [string] $SystemsManifest,

        [switch] $Rescan,

        [switch] $DryRun,

        [psobject] $Logger
    )

    # Cores: install those with a known catalog id.
    $coreIds = @($ProfileData.cores | Where-Object { $_.id } | ForEach-Object { [string]$_.id })
    $coreResult = $null
    if ($coreIds.Count -gt 0 -and $CoresManifest -and (Test-Path -LiteralPath $CoresManifest -PathType Leaf)) {
        $coreResult = Install-PocketCoreSet -Root $Root -CoresManifest $CoresManifest -Id $coreIds -DryRun:$DryRun -Logger $Logger
    }

    # ROM source mapping.
    $sources = @($ProfileData.romSources | ForEach-Object { [pscustomobject]@{ SystemId = $_.systemId; Path = $_.path; Recurse = [bool]$_.recurse } })
    if ($sources.Count -gt 0) { Save-PocketRomConfig -Root $Root -Sources $sources -DryRun:$DryRun | Out-Null }

    # Favourites per platform.
    $favRestored = 0
    foreach ($f in @($ProfileData.favorites)) {
        if (-not $f.platformId) { continue }
        Save-PocketFavorite -Root $Root -PlatformId ([string]$f.platformId) -Names @($f.names) -DryRun:$DryRun | Out-Null
        if (-not $DryRun) { Sync-PocketFavorite -Root $Root -PlatformId ([string]$f.platformId) | Out-Null }
        $favRestored++
    }

    # Optional: copy ROMs from the restored source folders.
    $rescanResult = $null
    if ($Rescan -and $SystemsManifest -and $sources.Count -gt 0) {
        $rescanResult = Invoke-PocketRomRescan -Root $Root -SystemsManifest $SystemsManifest -DryRun:$DryRun -Logger $Logger
    }

    [pscustomobject]@{
        PSTypeName        = 'PocketPrep.ProfileImportResult'
        CoresRequested    = $coreIds.Count
        CoreResult        = $coreResult
        RomSourcesRestored = $sources.Count
        FavoritesRestored = $favRestored
        Rescanned         = [bool]$Rescan
        RescanResult      = $rescanResult
        DryRun            = [bool]$DryRun
    }
}
