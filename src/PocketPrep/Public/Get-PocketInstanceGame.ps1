function Get-PocketInstanceGame {
<#
.SYNOPSIS
    Lists the per-game launch (instance) JSONs a core ships, and whether each game's
    data folder is present on the card.

.DESCRIPTION
    Some cores - notably Mazamars312's Neo Geo - do not load loose ROM files. The core
    zip ships one instance .json per supported game under Assets/<platformId>/<core>/,
    each declaring a data_path: the name of the game's data FOLDER the user must place
    in Assets/<platformId>/common/<data_path>/ (DarkSoft format for Neo Geo). The
    Pocket's menu launches games from those jsons.

    This read-only helper scans every core folder under Assets/<platformId>/ (anything
    that isn't 'common'), parses the instance jsons, and reports per game: the human
    Title (the json's file name), the DataPath folder it expects, and whether that
    folder is Installed under common with at least one file. It is the bridge between
    folder-format games and every display surface (library titles, box-art matching,
    health checks).

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform folder under Assets/ (e.g. 'ng').
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId
    )

    $platDir = Join-Path (Join-Path $Root 'Assets') $PlatformId
    $common  = Join-Path $platDir 'common'
    $games = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $platDir -PathType Container)) { return @() }

    foreach ($coreDir in (Get-ChildItem -LiteralPath $platDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'common' -and -not $_.Name.StartsWith('.') })) {
        foreach ($json in (Get-ChildItem -LiteralPath $coreDir.FullName -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
            $dataPath = $null
            $required = @()
            try {
                $parsed = Get-Content -LiteralPath $json.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
                $dataPath = [string]$parsed.instance.data_path
                # Per-game slot files the core will try to load from <data_path>/ (e.g.
                # srom/prom/crom0/m1rom/vroma0). A missing one is what triggers the core's
                # "Missing '<NAME>' ID [n]" launch error, so we surface it.
                $required = @($parsed.instance.data_slots | ForEach-Object { [string]$_.filename } | Where-Object { $_ })
            } catch {
                # Not an instance json (or malformed) - skip quietly; this is a scan.
                $null = $_
            }
            if (-not $dataPath) { continue }
            $gameDir = Join-Path $common $dataPath
            $present = @()
            if (Test-Path -LiteralPath $gameDir -PathType Container) {
                $present = @(Get-ChildItem -LiteralPath $gameDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
            }
            $installed = @($present).Count -gt 0
            # Case-insensitive presence check (FAT/exFAT are case-insensitive).
            $presentLower = @($present | ForEach-Object { $_.ToLowerInvariant() })
            $missing = @($required | Where-Object { $presentLower -notcontains $_.ToLowerInvariant() })
            $games.Add([pscustomobject]@{
                PSTypeName    = 'PocketPrep.InstanceGame'
                Title         = [System.IO.Path]::GetFileNameWithoutExtension($json.Name)
                DataPath      = $dataPath
                CoreFolder    = $coreDir.Name
                JsonPath      = $json.FullName
                Installed     = [bool]$installed
                RequiredFiles = $required
                # Only meaningful when the game folder exists; an absent game isn't "missing files".
                MissingFiles  = if ($installed) { $missing } else { @() }
            })
        }
    }
    @($games | Sort-Object Title)
}
