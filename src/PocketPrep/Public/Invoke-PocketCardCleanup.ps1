function Invoke-PocketCardCleanup {
<#
.SYNOPSIS
    Removes only the safe cleanup categories: empty sub-folders and the tool's temp dirs.

.DESCRIPTION
    Acts on Get-PocketCardCleanup, removing ONLY empty directories and the tool's own leftover
    ".pp-symlink-probe-*" folders (deepest-first). It NEVER removes a ROM, save, core, or any
    non-empty folder - unmanaged cores and orphan asset folders are reported by
    Get-PocketCardCleanup but left in place. Supports -DryRun.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER CoresManifest
    Optional path to manifests/cores.json (passed through to the scan).

.PARAMETER DryRun
    Report what would be removed without removing anything.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Removes only empty/temp directories (never files); -DryRun previews.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [string] $CoresManifest,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }
    $report = Get-PocketCardCleanup -Root $Root -CoresManifest $CoresManifest

    $removed = [System.Collections.Generic.List[string]]::new()
    # Probe dirs first (whole temp dirs), then empty dirs deepest-first so parents that become
    # empty are also cleared.
    $targets = @($report.ProbeDirs) + @($report.EmptyDirs | Sort-Object { $_.Length } -Descending)
    foreach ($dir in $targets) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $isProbe = (Split-Path -Leaf $dir) -like '.pp-symlink-probe-*'
        # Re-check emptiness at action time (a parent may have just been emptied).
        if (-not $isProbe -and (Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) { continue }
        if ($DryRun) { $removed.Add($dir); continue }
        try {
            Remove-Item -LiteralPath $dir -Recurse:$isProbe -Force -ErrorAction Stop
            $removed.Add($dir); & $log "CLEANUP removed $dir" 'INFO'
        } catch { & $log "CLEANUP failed to remove $dir : $_" 'WARN' }
    }

    [pscustomobject]@{
        PSTypeName   = 'PocketPrep.CardCleanupResult'
        RemovedCount = $removed.Count
        Removed      = $removed.ToArray()
        DryRun       = [bool]$DryRun
        # Carry the informational findings through so callers can show them.
        UnmanagedCores       = $report.UnmanagedCores
        OrphanAssetPlatforms = $report.OrphanAssetPlatforms
        SaveStateCount       = $report.SaveStateCount
    }
}
