function Get-PocketCardSummary {
<#
.SYNOPSIS
    Summarises what is already on a card (or fake SD root): firmware, cores, ROMs, config.

.DESCRIPTION
    A read-only breakdown for returning users - shown right after the drive is selected so
    they can see the card's current state and jump straight to a rescan or config edit
    instead of re-walking the wizard. Aggregates:
      - firmware: the root .bin file(s) and a best-effort version,
      - cores: Get-PocketInstalledCore (count + identifiers/versions),
      - ROMs: file counts per Assets/<platformId>/common (mapped to a system when the
        manifest is supplied),
      - config: whether a saved ROM source mapping (pocketprep/rom-sources.json) exists.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER SystemsManifest
    Optional path to manifests/systems.json, used to label ROM platform folders with their
    system id / display name.

.PARAMETER FirmwareManifest
    Optional path to manifests/firmware.json, used to resolve a firmware file name to a
    known version.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [string] $SystemsManifest,

        [string] $FirmwareManifest
    )

    # --- Firmware: the Pocket wants a single .bin at the root. -------------------------
    $binFiles = @(Get-ChildItem -LiteralPath $Root -Filter '*.bin' -File -ErrorAction SilentlyContinue)
    $fwVersionByName = @{}
    if ($FirmwareManifest -and (Test-Path -LiteralPath $FirmwareManifest -PathType Leaf)) {
        try {
            $fwm = Get-Content -LiteralPath $FirmwareManifest -Raw | ConvertFrom-Json
            foreach ($r in @($fwm.releases)) { if ($r.fileName) { $fwVersionByName[[string]$r.fileName] = [string]$r.version } }
        } catch { Write-Warning "Could not read firmware manifest: $_" }
    }
    $resolveFwVersion = {
        param($name)
        if ($fwVersionByName.ContainsKey($name)) { return $fwVersionByName[$name] }
        # Fall back to the conventional pocket_firmware_X_Y.bin naming.
        $m = [regex]::Match($name, 'pocket_firmware_(\d+)_(\d+)')
        if ($m.Success) { return "$($m.Groups[1].Value).$($m.Groups[2].Value)" }
        return 'unknown'
    }
    $primaryFw = $binFiles | Select-Object -First 1
    $firmware = [pscustomobject]@{
        Present    = [bool]$primaryFw
        FileName   = if ($primaryFw) { $primaryFw.Name } else { $null }
        Version    = if ($primaryFw) { & $resolveFwVersion $primaryFw.Name } else { $null }
        ExtraFiles = @($binFiles | Select-Object -Skip 1 | ForEach-Object { $_.Name })
    }

    # --- Cores ------------------------------------------------------------------------
    $cores = @(Get-PocketInstalledCore -Root $Root)

    # --- ROMs: count files per Assets/<platformId>/common ------------------------------
    $platformLabels = @{}
    if ($SystemsManifest -and (Test-Path -LiteralPath $SystemsManifest -PathType Leaf)) {
        try {
            foreach ($s in @(Get-PocketSystem -Path $SystemsManifest)) {
                if ($s.PlatformId) { $platformLabels[[string]$s.PlatformId] = $s }
            }
        } catch { Write-Warning "Could not read systems manifest: $_" }
    }
    $assetsDir = Join-Path $Root 'Assets'
    $romSystems = if (Test-Path -LiteralPath $assetsDir -PathType Container) {
        foreach ($pdir in Get-ChildItem -LiteralPath $assetsDir -Directory -ErrorAction SilentlyContinue) {
            $common = Join-Path $pdir.FullName 'common'
            if (-not (Test-Path -LiteralPath $common -PathType Container)) { continue }
            # Don't count the tool-managed Favorites folder (symlinks/copies) as extra ROMs.
            $favPrefix = (Join-Path $common 'Favorites') + [System.IO.Path]::DirectorySeparatorChar
            $count = @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { -not $_.FullName.StartsWith($favPrefix, [System.StringComparison]::OrdinalIgnoreCase) }).Count
            if ($count -eq 0) { continue }
            $sys = $platformLabels[$pdir.Name]
            [pscustomobject]@{
                PlatformId  = $pdir.Name
                SystemId    = if ($sys) { $sys.Id } else { $null }
                DisplayName = if ($sys) { $sys.DisplayName } else { $pdir.Name }
                FileCount   = $count
            }
        }
    }
    $romSystems = @($romSystems | Sort-Object DisplayName)
    $totalRoms = (@($romSystems | Measure-Object -Property FileCount -Sum).Sum) ?? 0

    # --- BIOS status for BIOS-dependent systems (e.g. Neo Geo) -------------------------
    $bios = if ($SystemsManifest -and (Test-Path -LiteralPath $SystemsManifest -PathType Leaf)) {
        @(Get-PocketBiosStatus -Root $Root -SystemsManifest $SystemsManifest)
    } else { @() }

    # --- Saved ROM config (#117) -------------------------------------------------------
    $config = Get-PocketRomConfig -Root $Root

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.CardSummary'
        Root       = $Root
        Firmware   = $firmware
        Cores      = [pscustomobject]@{
            Count = $cores.Count
            Items = @($cores | ForEach-Object { [pscustomobject]@{ Identifier = $_.Identifier; Version = $_.Version } })
        }
        Roms       = [pscustomobject]@{
            TotalFiles = $totalRoms
            Systems    = $romSystems
        }
        Config     = [pscustomobject]@{
            Exists      = $config.Exists
            SourceCount = @($config.Sources).Count
        }
        Bios       = @($bios)
    }
}
