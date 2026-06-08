function Get-PocketRomConfig {
<#
.SYNOPSIS
    Reads the saved ROM source mapping from a card (or fake SD root).

.DESCRIPTION
    Returns the ROM library config stored at pocketprep/rom-sources.json on the card.
    The config records which source folders map to which system, so a later run can
    rescan for new ROMs without walking the whole wizard. It never contains ROMs - only
    paths and options.

    When no config exists (or it cannot be parsed) an empty, valid config is returned with
    Exists = $false, so callers can treat "first run" and "returning user" the same way.

.PARAMETER Root
    SD card root or fake SD root folder.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root
    )

    $path = Join-Path (Join-Path $Root 'pocketprep') 'rom-sources.json'
    $empty = [pscustomobject]@{
        PSTypeName = 'PocketPrep.RomConfig'
        Version    = 1
        Sources    = @()
        Path       = $path
        Exists     = $false
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $empty }

    try {
        $raw = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse ${path}: $_ - treating as no saved config."
        return $empty
    }

    $sources = foreach ($s in @($raw.sources)) {
        if (-not $s.systemId -or -not $s.path) { continue }   # skip malformed rows
        [pscustomobject]@{
            SystemId = [string]$s.systemId
            Path     = [string]$s.path
            Recurse  = [bool]$s.recurse
        }
    }
    [pscustomobject]@{
        PSTypeName = 'PocketPrep.RomConfig'
        Version    = if ($raw.version) { [int]$raw.version } else { 1 }
        Sources    = @($sources)
        Path       = $path
        Exists     = $true
    }
}
