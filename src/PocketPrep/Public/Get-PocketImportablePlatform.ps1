function Get-PocketImportablePlatform {
<#
.SYNOPSIS
    Lists ROM-importable platforms declared by installed cores but not in the systems manifest.

.DESCRIPTION
    ROM import is normally driven by manifests/systems.json (the well-known systems). When a
    user installs other cores, those cores declare their own platform_ids in core.json - and
    that declaration is the AUTHORITATIVE ROM destination (Assets/<platformId>/common). Rather
    than guess platform-ids for every possible core (which risks misplacing ROMs), this reads
    the platform_ids straight from the installed cores and returns any not already covered by
    the manifest, shaped like a system object so it can be passed to New-PocketRomCopyPlan.

    Returned objects use SupportedExtensions = @('*') (match any file), since the exact ROM
    extensions for an arbitrary core aren't known - callers should warn the user accordingly.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER SystemsManifest
    Path to manifests/systems.json (its platformIds are treated as already covered).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $SystemsManifest
    )

    $covered = @{}
    try {
        foreach ($s in @(Get-PocketSystem -Path $SystemsManifest)) {
            if ($s.PlatformId) { $covered[[string]$s.PlatformId.ToLowerInvariant()] = $true }
        }
    } catch { Write-Warning "Could not read systems manifest: $_" }

    $seen = @{}
    $result = foreach ($core in @(Get-PocketInstalledCore -Root $Root)) {
        foreach ($platId in @($core.PlatformIds)) {
            if (-not $platId) { continue }
            $key = ([string]$platId).ToLowerInvariant()
            if ($covered.ContainsKey($key) -or $seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            [pscustomobject]@{
                PSTypeName          = 'PocketPrep.ImportablePlatform'
                Id                  = [string]$platId
                PlatformId          = [string]$platId
                DisplayName         = "$platId (from $($core.Identifier))"
                Manufacturer        = ''
                SupportedExtensions = @('*')
                RequiresCore        = $true
                SuggestedCore       = $core.Identifier
                BiosRequired        = $false
                BiosFiles           = @()
                Experimental        = $true
                FromCore            = $core.Identifier
                Notes               = "Platform declared by the installed core '$($core.Identifier)'. ROM extensions are not known to this tool, so any file you point at it will be copied to Assets/$platId/common - make sure the folder contains only ROMs for this system."
            }
        }
    }
    return @($result)
}
