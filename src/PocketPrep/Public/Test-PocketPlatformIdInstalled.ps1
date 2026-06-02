function Test-PocketPlatformIdInstalled {
<#
.SYNOPSIS
    Reports whether any installed core declares a given platform_id.

.DESCRIPTION
    ROMs for a system go to Assets/<platformId>/common, but the platform_id is defined
    by the core. This checks the installed cores' declared platform_ids (from core.json)
    so the wizard/UI can warn when ROMs are about to be copied for a platform no
    installed core actually provides.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform id to look for (e.g. 'gb', 'nes').

.PARAMETER InstalledCore
    Optionally pass pre-fetched Get-PocketInstalledCore output to avoid re-scanning.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $PlatformId,
        [psobject[]] $InstalledCore
    )

    if (-not $PSBoundParameters.ContainsKey('InstalledCore')) {
        $InstalledCore = Get-PocketInstalledCore -Root $Root
    }

    $providers = @($InstalledCore | Where-Object { $_.PlatformIds -contains $PlatformId } | ForEach-Object { $_.Identifier })

    [pscustomobject]@{
        PSTypeName  = 'PocketPrep.PlatformIdCheck'
        PlatformId  = $PlatformId
        Installed   = ($providers.Count -gt 0)
        ProvidedBy  = $providers
    }
}
