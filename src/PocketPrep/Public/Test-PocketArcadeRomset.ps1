function Test-PocketArcadeRomset {
<#
.SYNOPSIS
    Reports whether an arcade platform has any playable game files (instance .json + .rom).

.DESCRIPTION
    Arcade cores load games via an instance .json plus a built .rom in
    Assets/<platformId>/common. This read-only check counts both under the platform's
    common folder (excluding the tool-managed favourites folders) so the UI can say whether
    any games are actually playable, instead of just counting copied files.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The arcade platform to check.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId
    )

    $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'
    $json = 0; $rom = 0
    if (Test-Path -LiteralPath $common -PathType Container) {
        $commonFull = (Resolve-Path -LiteralPath $common).Path
        foreach ($f in @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue)) {
            if (Test-PocketReservedRomPath -Common $commonFull -FullPath $f.FullName) { continue }
            switch ($f.Extension.ToLowerInvariant()) {
                '.json' { $json++ }
                '.rom'  { $rom++ }
            }
        }
    }
    [pscustomobject]@{
        PSTypeName    = 'PocketPrep.ArcadeRomsetStatus'
        PlatformId    = $PlatformId
        InstanceJson  = $json
        BuiltRom      = $rom
        Ready         = ($json -gt 0 -and $rom -gt 0)
    }
}
