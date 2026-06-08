function Import-PocketUsedCard {
<#
.SYNOPSIS
    Onboards an already-used card: scans its content and generates a starter ROM config.

.DESCRIPTION
    For a card that already has ROMs but no saved source mapping (pocketprep/rom-sources.json),
    this builds the tool's understanding of the card. It reads the card breakdown
    (Get-PocketCardSummary) and, for each populated Assets/<platformId>/common that maps to a
    known system, writes a config source entry so the rescan / add-folder workflow (#117) and
    the breakdown (#120) light up immediately.

    Each generated entry records the card's own Assets/<platformId>/common as the initial
    source path. That keeps the config valid and makes a first rescan a safe no-op (every file
    is already present, so nothing is copied); the user can then re-point each source at their
    computer's ROM folder via the Browse picker. Existing config entries are preserved.

    Nothing is ever downloaded or deleted - this only reads the card and writes the small JSON
    config (paths + options, never ROMs).

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER SystemsManifest
    Path to manifests/systems.json, used to map platform folders to a system id.

.PARAMETER FirmwareManifest
    Optional path to manifests/firmware.json (forwarded to the summary for firmware version).

.PARAMETER DryRun
    Report what would be onboarded without writing the config.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $SystemsManifest,

        [string] $FirmwareManifest,

        [switch] $DryRun
    )

    $summary = Get-PocketCardSummary -Root $Root -SystemsManifest $SystemsManifest -FirmwareManifest $FirmwareManifest
    $existing = Get-PocketRomConfig -Root $Root

    $detected = [System.Collections.Generic.List[object]]::new()
    $unmapped = [System.Collections.Generic.List[object]]::new()
    foreach ($s in @($summary.Roms.Systems)) {
        if (-not $s.SystemId) {
            # ROMs present for a platform with no matching system in the manifest - report it
            # so the user knows (it can still be handled once a core declares the platform).
            $unmapped.Add([pscustomobject]@{ PlatformId = $s.PlatformId; FileCount = $s.FileCount })
            continue
        }
        $detected.Add([pscustomobject]@{
            SystemId = $s.SystemId
            Path     = Join-Path (Join-Path (Join-Path $Root 'Assets') $s.PlatformId) 'common'
            Recurse  = $false
        })
    }

    # Merge: newly detected entries first so they win the system+path de-dup, then keep any
    # source folders the user had already saved.
    $merged = @($detected) + @($existing.Sources)
    $saved = Save-PocketRomConfig -Root $Root -Sources $merged -DryRun:$DryRun

    [pscustomobject]@{
        PSTypeName     = 'PocketPrep.UsedCardImport'
        Summary        = $summary
        DetectedCount  = $detected.Count
        Detected       = $detected.ToArray()
        UnmappedCount  = $unmapped.Count
        Unmapped       = $unmapped.ToArray()
        Config         = $saved
        DryRun         = [bool]$DryRun
    }
}
