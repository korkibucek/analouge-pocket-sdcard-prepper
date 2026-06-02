function New-PocketInstallSummary {
<#
.SYNOPSIS
    Builds a structured summary of an install run and a human-readable rendering.

.DESCRIPTION
    Collects the firmware result, folder result, and per-system ROM results into one
    object with a .ToString() that prints a clean summary for the final screen and
    the log file.

.PARAMETER Target
    The PocketPrep.Target used for the run.

.PARAMETER FirmwareResult
    Result from Install-PocketFirmware (or $null if skipped).

.PARAMETER FolderResult
    Result from New-PocketFolderStructure (or $null if skipped).

.PARAMETER RomResults
    Array of results from Invoke-PocketRomCopyPlan.
#>
    [CmdletBinding()]
    param(
        [psobject] $Target,
        [psobject] $FirmwareResult,
        [psobject] $FolderResult,
        [psobject[]] $RomResults = @(),
        [psobject[]] $CoreResults = @()
    )

    $totalRoms = ($RomResults | Measure-Object -Property CopiedCount -Sum).Sum
    if (-not $totalRoms) { $totalRoms = 0 }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('==== Analogue Pocket SD Card Prepper - Summary ====')
    if ($Target) {
        $lines.Add("Target: $($Target.Root)" + $(if ($Target.IsTestMode) { '  (TEST MODE - not a real SD card)' } else { '' }))
    }

    if ($FirmwareResult) {
        $fw = "Firmware: v$($FirmwareResult.Version) -> $($FirmwareResult.FileName)"
        if ($FirmwareResult.DryRun) { $fw += ' [dry-run]' }
        elseif ($FirmwareResult.Md5Verified) { $fw += ' [MD5 verified]' }
        else { $fw += ' [NOT checksum-verified]' }
        $lines.Add($fw)
    } else {
        $lines.Add('Firmware: skipped')
    }

    if ($FolderResult) {
        $lines.Add("Folders created: $($FolderResult.Created.Count); already present: $($FolderResult.Existing.Count)")
    } else {
        $lines.Add('Folders: skipped')
    }

    if ($CoreResults.Count -gt 0) {
        $lines.Add("Cores installed: $($CoreResults.Count)")
        foreach ($c in $CoreResults) {
            $tag = if ($c.DryRun) { ' [dry-run]' } else { '' }
            $lines.Add(("  - {0}: {1} files placed, {2} skipped (v{3}){4}" -f $c.Identifier, $c.PlacedCount, $c.SkippedCount, $c.Version, $tag))
        }
    } else {
        $lines.Add('Cores: none installed')
    }

    if ($RomResults.Count -gt 0) {
        $lines.Add("ROMs copied: $totalRoms total across $($RomResults.Count) system(s)")
        foreach ($r in $RomResults) {
            $tag = if ($r.DryRun) { ' [dry-run]' } else { '' }
            $lines.Add(("  - {0}: {1} copied, {2} skipped, {3} failed{4}" -f $r.SystemId, $r.CopiedCount, $r.SkippedCount, $r.FailedCount, $tag))
        }
    } else {
        $lines.Add('ROMs: none imported')
    }
    $lines.Add('===================================================')

    $summary = [pscustomobject]@{
        PSTypeName     = 'PocketPrep.InstallSummary'
        TargetRoot     = $Target.Root
        IsTestMode     = [bool]$Target.IsTestMode
        FirmwareResult = $FirmwareResult
        FolderResult   = $FolderResult
        RomResults     = $RomResults
        CoreResults    = $CoreResults
        TotalRomsCopied = $totalRoms
        Text           = ($lines -join [Environment]::NewLine)
    }

    $summary | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.Text } -Force
    return $summary
}
