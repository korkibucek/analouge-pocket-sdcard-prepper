function Invoke-PocketRomOrganizePlan {
<#
.SYNOPSIS
    Executes a ROM organize plan from New-PocketRomOrganizePlan (moves/renames only).

.DESCRIPTION
    Moves each planned file to its destination subfolder. This is the tool's only operation
    that RELOCATES existing user content - it is move/rename only: nothing is ever deleted or
    overwritten. If a destination unexpectedly already exists it is skipped (never clobbered).
    Each move is size-verified. Empty subfolders left behind under the platform's common folder
    are pruned afterwards (directory removal only - never files). Supports -DryRun.

.PARAMETER Plan
    A plan object from New-PocketRomOrganizePlan.

.PARAMETER DryRun
    Report actions without moving anything.

.PARAMETER OnProgress
    Optional callback: & $OnProgress $done $total $name.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Move/rename only (no delete/overwrite); -DryRun provides the preview path.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Plan,

        [switch] $DryRun,

        [scriptblock] $OnProgress,

        [psobject] $Logger
    )

    process {
        $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

        $moved   = [System.Collections.Generic.List[object]]::new()
        $skipped = [System.Collections.Generic.List[object]]::new()
        $failed  = [System.Collections.Generic.List[object]]::new()

        $todo = @($Plan.Items | Where-Object { $_.Action -ne 'None' })
        $total = $todo.Count
        $done = 0

        foreach ($item in $todo) {
            $done++
            if ($OnProgress) { & $OnProgress $done $total $item.Source }

            if ($DryRun) {
                $moved.Add([pscustomobject]@{ From = $item.Source; To = $item.Destination; Action = $item.Action })
                & $log "DRYRUN would $($item.Action.ToLowerInvariant()) $($item.Source) -> $($item.Destination)" 'INFO'
                continue
            }

            # Never clobber an existing different file.
            if ((Test-Path -LiteralPath $item.Destination) -and ($item.Destination -ne $item.Source)) {
                $skipped.Add([pscustomobject]@{ From = $item.Source; To = $item.Destination; Reason = 'destination exists' })
                & $log "SKIP (exists) $($item.Destination)" 'WARN'
                continue
            }

            try {
                $destDir = Split-Path -Parent $item.Destination
                if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
                $srcLen = (Get-Item -LiteralPath $item.Source).Length
                Move-Item -LiteralPath $item.Source -Destination $item.Destination
                $dstLen = (Get-Item -LiteralPath $item.Destination -ErrorAction SilentlyContinue).Length
                if ($dstLen -ne $srcLen) { throw "size mismatch after move (expected $srcLen, got $dstLen)" }
                $moved.Add([pscustomobject]@{ From = $item.Source; To = $item.Destination; Action = $item.Action })
                & $log "$($item.Action.ToUpperInvariant()) $($item.Source) -> $($item.Destination)" 'INFO'
            } catch {
                $failed.Add([pscustomobject]@{ From = $item.Source; To = $item.Destination; Error = "$_" })
                & $log "FAILED $($item.Source): $_" 'ERROR'
            }
        }

        # Prune empty subfolders left under common (directories only, never files).
        $prunedDirs = 0
        if (-not $DryRun -and $Plan.Common -and (Test-Path -LiteralPath $Plan.Common -PathType Container)) {
            $subDirs = @(Get-ChildItem -LiteralPath $Plan.Common -Directory -Recurse -ErrorAction SilentlyContinue) |
                Sort-Object { $_.FullName.Length } -Descending
            foreach ($d in $subDirs) {
                if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue
                    $prunedDirs++
                }
            }
        }

        [pscustomobject]@{
            PSTypeName    = 'PocketPrep.RomOrganizeResult'
            PlatformId    = $Plan.PlatformId
            DryRun        = [bool]$DryRun
            MovedCount    = $moved.Count
            RenamedCount  = @($moved | Where-Object { $_.Action -eq 'Rename' }).Count
            SkippedCount  = $skipped.Count
            FailedCount   = $failed.Count
            PrunedDirs    = $prunedDirs
            Moved         = $moved.ToArray()
            Skipped       = $skipped.ToArray()
            Failed        = $failed.ToArray()
        }
    }
}
