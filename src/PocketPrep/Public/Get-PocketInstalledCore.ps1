function Get-PocketInstalledCore {
<#
.SYNOPSIS
    Lists openFPGA cores already installed on a card (or fake SD root).

.DESCRIPTION
    Reads each Cores/<identifier>/core.json and returns the core's metadata: identifier
    (folder name), author, shortname, version, release date, and the declared
    platform_ids. The platform_ids are authoritative for where ROMs go
    (Assets/<platformId>/common), so this is also how the tool can verify or correct the
    manifest's ROM destinations.

.PARAMETER Root
    SD card root or fake SD root folder.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root
    )

    $coresDir = Join-Path $Root 'Cores'
    if (-not (Test-Path -LiteralPath $coresDir -PathType Container)) {
        return @()
    }

    $result = foreach ($dir in Get-ChildItem -LiteralPath $coresDir -Directory) {
        $coreJson = Join-Path $dir.FullName 'core.json'
        if (-not (Test-Path -LiteralPath $coreJson -PathType Leaf)) { continue }
        try {
            $meta = (Get-Content -LiteralPath $coreJson -Raw | ConvertFrom-Json).core.metadata
        } catch {
            Write-Warning "Could not parse ${coreJson}: $_"
            continue
        }
        [pscustomobject]@{
            PSTypeName  = 'PocketPrep.InstalledCore'
            Identifier  = $dir.Name
            ShortName   = [string]$meta.shortname
            Author      = [string]$meta.author
            Version     = [string]$meta.version
            ReleaseDate = [string]$meta.date_release
            PlatformIds = @($meta.platform_ids)
            Path        = $dir.FullName
        }
    }
    return @($result)
}
