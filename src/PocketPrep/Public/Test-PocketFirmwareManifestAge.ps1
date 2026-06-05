function Test-PocketFirmwareManifestAge {
<#
.SYNOPSIS
    Reports whether the firmware manifest looks out of date.

.DESCRIPTION
    Analogue ships firmware updates over time, but this tool's firmware data lives in a
    static manifest. This is a no-network check: if the newest release in the manifest is
    older than the warning threshold, callers should advise the user to check the official
    firmware page (and the project should refresh the manifest). The scheduled
    firmware-check CI workflow detects new official releases automatically.

.PARAMETER Manifest
    A manifest object from Get-PocketFirmwareManifest.

.PARAMETER WarnAfterDays
    Age (in days) of the newest release beyond which the manifest is considered stale.
    Default 270 (~9 months).

.PARAMETER AsOfDate
    The reference "today" (for testing). Defaults to the current date.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Manifest,
        [int] $WarnAfterDays = 270,
        [datetime] $AsOfDate = (Get-Date)
    )

    $dates = foreach ($r in $Manifest.releases) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact([string]$r.releaseDate, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            $parsed
        }
    }
    $newest = if ($dates) { ($dates | Sort-Object -Descending | Select-Object -First 1) } else { $null }
    $ageDays = if ($newest) { [int]($AsOfDate.Date - $newest.Date).TotalDays } else { $null }

    [pscustomobject]@{
        PSTypeName        = 'PocketPrep.FirmwareAge'
        NewestReleaseDate = if ($newest) { $newest.ToString('yyyy-MM-dd') } else { $null }
        AgeDays           = $ageDays
        WarnAfterDays     = $WarnAfterDays
        Stale             = ($null -ne $ageDays -and $ageDays -gt $WarnAfterDays)
    }
}
