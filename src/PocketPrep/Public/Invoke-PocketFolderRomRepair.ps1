function Invoke-PocketFolderRomRepair {
<#
.SYNOPSIS
    Applies a folder-format repair plan - renames mis-named game folders to the core's
    expected data_path. Rename-only, never deletes/converts/overwrites.

.DESCRIPTION
    Runs Get-PocketFolderRomRepairPlan and performs its safe renames (a folder move to
    the core's data_path, e.g. "Metal Slug 4" -> "mslug4"). This is the only auto-fix:
    folders missing slot files, un-converted MAME romsets, and unidentifiable folders are
    reported (Attention) and left untouched - the tool never converts or downloads ROM
    data. A rename is trivially reversible.

      - Nothing is deleted or overwritten: a rename whose target already exists is skipped
        (reported as a conflict), never clobbered.
      - -DryRun previews the renames without touching the card; the web API forces a
        dry-run unless the caller explicitly confirms.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The folder-format platform (e.g. 'ng').

.PARAMETER SystemsManifest
    Path to manifests/systems.json.

.PARAMETER DryRun
    Report the renames that would happen; rename nothing.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Guarded, reversible rename-only op with a -DryRun preview and confirm-gated API.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Root,
        [Parameter(Mandatory, Position = 1)] [string] $PlatformId,
        [Parameter(Position = 2)] [string] $SystemsManifest,
        [switch] $DryRun,
        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }
    $plan = Get-PocketFolderRomRepairPlan -Root $Root -PlatformId $PlatformId -SystemsManifest $SystemsManifest
    $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'

    $renamed = [System.Collections.Generic.List[object]]::new()
    $skipped = [System.Collections.Generic.List[object]]::new()
    if (-not $DryRun) {
        foreach ($r in @($plan.Renames)) {
            $from = Join-Path $common $r.From
            $to = Join-Path $common $r.To
            if (Test-Path -LiteralPath $to) {
                # Target appeared since planning - never overwrite.
                $skipped.Add([pscustomobject]@{ From = $r.From; To = $r.To; Reason = 'target already exists' })
                & $log "SKIP rename $($r.From) -> $($r.To): target exists" 'WARN'
                continue
            }
            try {
                Move-Item -LiteralPath $from -Destination $to
                $renamed.Add([pscustomobject]@{ From = $r.From; To = $r.To; Title = $r.Title })
                & $log "REPAIR renamed game folder $($r.From) -> $($r.To)" 'WARN'
            } catch {
                $skipped.Add([pscustomobject]@{ From = $r.From; To = $r.To; Reason = "$_" })
                & $log "FAILED rename $($r.From) -> $($r.To): $_" 'ERROR'
            }
        }
    }

    [pscustomobject]@{
        PSTypeName     = 'PocketPrep.FolderRomRepairResult'
        PlatformId     = $PlatformId
        DisplayName    = $plan.DisplayName
        CoreInstalled  = $plan.CoreInstalled
        DryRun         = [bool]$DryRun
        # On a dry-run, "Renamed" reflects what WOULD be renamed (the plan); on apply it's
        # what actually was.
        Renamed        = if ($DryRun) { @($plan.Renames) } else { $renamed.ToArray() }
        RenamedCount   = if ($DryRun) { $plan.RenameCount } else { $renamed.Count }
        Skipped        = $skipped.ToArray()
        Attention      = $plan.Attention
        AttentionCount = $plan.AttentionCount
        OkCount        = $plan.OkCount
    }
}
