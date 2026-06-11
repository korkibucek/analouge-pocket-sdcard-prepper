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
            try {
                $parsed = Get-Content -LiteralPath $json.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
                $dataPath = [string]$parsed.instance.data_path
            } catch {
                # Not an instance json (or malformed) - skip quietly; this is a scan.
                $null = $_
            }
            if (-not $dataPath) { continue }
            $gameDir = Join-Path $common $dataPath
            $installed = (Test-Path -LiteralPath $gameDir -PathType Container) -and
                (@(Get-ChildItem -LiteralPath $gameDir -File -ErrorAction SilentlyContinue).Count -gt 0)
            $games.Add([pscustomobject]@{
                PSTypeName = 'PocketPrep.InstanceGame'
                Title      = [System.IO.Path]::GetFileNameWithoutExtension($json.Name)
                DataPath   = $dataPath
                CoreFolder = $coreDir.Name
                JsonPath   = $json.FullName
                Installed  = [bool]$installed
            })
        }
    }
    @($games | Sort-Object Title)
}
