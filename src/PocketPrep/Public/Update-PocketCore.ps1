function Update-PocketCore {
<#
.SYNOPSIS
    Updates installed cores that have a newer GitHub release.

.DESCRIPTION
    Finds installed cores whose latest release is newer than the installed version and
    reinstalls them (download + overwrite). Supports -DryRun (reports what would update
    without writing or downloading). The update status can be supplied via -UpdateStatus
    to avoid the network (used by tests).

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER CoresManifest
    Path to cores.json (for owner/repo lookup).

.PARAMETER UpdateStatus
    Optional pre-computed Get-PocketCoreUpdateStatus output (skips the network check).

.PARAMETER DryRun
    Report what would be updated without downloading or writing.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Forwarded to Install-PocketCore.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $CoresManifest,
        [psobject[]] $UpdateStatus,
        [switch] $DryRun,
        [psobject] $Logger
    )

    if (-not $PSBoundParameters.ContainsKey('UpdateStatus')) {
        $UpdateStatus = Get-PocketCoreUpdateStatus -Root $Root -CoresManifest $CoresManifest
    }
    $manifestCores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest)

    $toUpdate = @($UpdateStatus | Where-Object { $_.UpdateAvailable })
    $results = foreach ($st in $toUpdate) {
        if ($DryRun) {
            [pscustomobject]@{
                PSTypeName = 'PocketPrep.CoreUpdateResult'
                Identifier = $st.Identifier; From = $st.Installed; To = $st.Latest
                Action = 'would-update'; DryRun = $true; PlacedCount = 0; Error = $null
            }
            continue
        }
        $core = $manifestCores | Where-Object { $_.Identifier -ieq $st.Identifier } | Select-Object -First 1
        if (-not $core) {
            [pscustomobject]@{ PSTypeName='PocketPrep.CoreUpdateResult'; Identifier=$st.Identifier
                From=$st.Installed; To=$st.Latest; Action='skipped'; DryRun=$false; PlacedCount=0
                Error='not in manifest' }
            continue
        }
        try {
            $r = Install-PocketCore -Root $Root -Core $core -Download -Overwrite -Logger $Logger
            [pscustomobject]@{ PSTypeName='PocketPrep.CoreUpdateResult'; Identifier=$st.Identifier
                From=$st.Installed; To=$r.Version; Action='updated'; DryRun=$false
                PlacedCount=$r.PlacedCount; Error=$null }
        } catch {
            [pscustomobject]@{ PSTypeName='PocketPrep.CoreUpdateResult'; Identifier=$st.Identifier
                From=$st.Installed; To=$st.Latest; Action='failed'; DryRun=$false; PlacedCount=0
                Error="$($_.Exception.Message)" }
        }
    }
    return @($results)
}
