function Get-PocketCoreUpdateStatus {
<#
.SYNOPSIS
    Checks installed cores against their latest GitHub release and reports updates.

.DESCRIPTION
    For each installed core that maps to an entry in the cores manifest (matched by
    identifier), resolves the latest release version from GitHub and compares it with
    the installed version. Network-bound. Cores not in the manifest are reported with
    Latest = null (we don't know where to look).

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER CoresManifest
    Path to cores.json (for owner/repo lookup).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $CoresManifest
    )

    $installed = Get-PocketInstalledCore -Root $Root
    $manifestCores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest)

    foreach ($ic in $installed) {
        $mc = $manifestCores | Where-Object { $_.Identifier -ieq $ic.Identifier } | Select-Object -First 1
        $latest = $null; $err = $null
        if ($mc) {
            try { $latest = (Get-PocketLatestRelease -Owner $mc.Owner -Repo $mc.Repo).Version }
            catch { $err = "$($_.Exception.Message)" }
        }
        $cmp = if ($latest) { Compare-PocketVersion -Installed $ic.Version -Latest $latest } else { $null }
        [pscustomobject]@{
            PSTypeName      = 'PocketPrep.CoreUpdateStatus'
            Identifier      = $ic.Identifier
            Installed       = $ic.Version
            Latest          = $latest
            UpdateAvailable = if ($cmp) { $cmp.UpdateAvailable } else { $false }
            InManifest      = [bool]$mc
            Error           = $err
        }
    }
}
