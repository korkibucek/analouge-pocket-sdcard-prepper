function Get-PocketCoreRequiredFile {
<#
.SYNOPSIS
    Reports required files (e.g. BIOS) each installed core declares but is missing on the card.

.DESCRIPTION
    Reads every installed core's data.json and inspects data.data_slots. A slot that is
    required AND names a fixed filename is a file the core needs at load (typically a BIOS /
    boot ROM) - as opposed to a required slot with no filename, which is just the user's
    cartridge/ROM. This is the data.json-driven generalisation of the Neo Geo BIOS check: it
    is correct for ANY core, with no hard-coded list, and it NEVER downloads anything - it
    only detects what's present and guides the user to supply the rest.

    A data-slot file is looked for under Assets/<platformId>/common/<filename> and the
    core-specific Assets/<platformId>/<identifier>/<filename>; present in either => satisfied.

.PARAMETER Root
    SD card root or fake SD root folder.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root
    )

    $result = foreach ($core in @(Get-PocketInstalledCore -Root $Root)) {
        $dataJson = Join-Path $core.Path 'data.json'
        if (-not (Test-Path -LiteralPath $dataJson -PathType Leaf)) { continue }
        try {
            $slots = (Get-Content -LiteralPath $dataJson -Raw | ConvertFrom-Json).data.data_slots
        } catch {
            Write-Warning "Could not parse $dataJson : $_"
            continue
        }

        $platformIds = @($core.PlatformIds)
        $required = foreach ($slot in @($slots)) {
            $fname = [string]$slot.filename
            if (-not ($slot.required -and $fname)) { continue }   # required cartridge slots have no filename
            $found = $false; $location = $null
            foreach ($p in $platformIds) {
                $assets = Join-Path (Join-Path $Root 'Assets') $p
                foreach ($cand in @((Join-Path (Join-Path $assets 'common') $fname),
                                    (Join-Path (Join-Path $assets $core.Identifier) $fname))) {
                    if (Test-Path -LiteralPath $cand -PathType Leaf) { $found = $true; $location = $cand; break }
                }
                if ($found) { break }
            }
            $expect = if ($platformIds.Count) { Join-Path (Join-Path (Join-Path (Join-Path $Root 'Assets') $platformIds[0]) 'common') $fname } else { $fname }
            [pscustomobject]@{
                Name     = [string]$slot.name
                Filename = $fname
                Found    = $found
                Location = if ($found) { $location } else { $expect }
            }
        }
        $required = @($required)
        if ($required.Count -eq 0) { continue }
        $missing = @($required | Where-Object { -not $_.Found })
        [pscustomobject]@{
            PSTypeName   = 'PocketPrep.CoreRequiredFiles'
            Identifier   = $core.Identifier
            PlatformId   = if ($platformIds.Count) { $platformIds[0] } else { $null }
            Required     = $required
            MissingCount = $missing.Count
            Missing      = @($missing | ForEach-Object { $_.Filename })
            Satisfied    = ($missing.Count -eq 0)
        }
    }
    return @($result)
}
