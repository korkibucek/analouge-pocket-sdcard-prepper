function Get-PocketKnownPlatform {
<#
.SYNOPSIS
    Lists every ROM-importable platform the tool knows about, for the "upload ROMs" picker.

.DESCRIPTION
    Unions three sources so ROM upload can target ANY core, not just the built-in systems:
      1. built-in systems (manifests/systems.json) - with their real ROM extensions,
      2. platforms declared by cores already installed on the card (authoritative
         destinations; only when -Root is given), and
      3. every platformId in the cores catalog (manifests/cores.json) - match-all ('*')
         extensions, since the catalog doesn't record exact ROM extensions.
    De-duplicated by platformId (case-insensitive); a built-in system wins over an installed
    core, which wins over a catalog entry. A free-text custom platform-id (handled by the
    caller) covers anything still not listed.

.PARAMETER SystemsManifest
    Path to manifests/systems.json.

.PARAMETER CoresManifest
    Optional path to manifests/cores.json (the catalog).

.PARAMETER Root
    Optional SD root; when given, installed cores' declared platforms are included.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $SystemsManifest,

        [string] $CoresManifest,

        [string] $Root
    )

    $byId = [ordered]@{}
    $add = {
        param($obj)
        $key = ([string]$obj.PlatformId).ToLowerInvariant()
        if ($key -and -not $byId.Contains($key)) { $byId[$key] = $obj }
    }

    # 1. Built-in systems (real extensions).
    foreach ($s in @(Get-PocketSystem -Path $SystemsManifest)) {
        & $add ([pscustomobject]@{
            Id = $s.Id; PlatformId = $s.PlatformId; DisplayName = $s.DisplayName
            SupportedExtensions = @($s.SupportedExtensions); Source = 'system'
            Experimental = [bool]$s.Experimental; BiosRequired = [bool]$s.BiosRequired
            Notes = [string]$s.Notes
        })
    }

    # 2. Platforms from cores installed on the card (authoritative).
    if ($Root) {
        foreach ($p in @(Get-PocketImportablePlatform -Root $Root -SystemsManifest $SystemsManifest)) {
            & $add ([pscustomobject]@{
                Id = $p.Id; PlatformId = $p.PlatformId; DisplayName = $p.DisplayName
                SupportedExtensions = @('*'); Source = 'installed-core'
                Experimental = $true; BiosRequired = $false; Notes = [string]$p.Notes
            })
        }
    }

    # 3. Every platform in the cores catalog.
    if ($CoresManifest -and (Test-Path -LiteralPath $CoresManifest -PathType Leaf)) {
        try {
            foreach ($c in @(Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest))) {
                foreach ($platId in @($c.PlatformIds)) {
                    if (-not $platId) { continue }
                    & $add ([pscustomobject]@{
                        Id = [string]$platId; PlatformId = [string]$platId
                        DisplayName = "$platId ($($c.DisplayName))"
                        SupportedExtensions = @('*'); Source = 'catalog'
                        Experimental = $true; BiosRequired = [bool]$c.BiosRequired
                        Notes = "Catalog platform from core '$($c.Identifier)'. ROM extensions unknown - any file you point at it is copied to Assets/$platId/common."
                    })
                }
            }
        } catch { Write-Warning "Could not read cores catalog: $_" }
    }

    return @($byId.Values)
}
