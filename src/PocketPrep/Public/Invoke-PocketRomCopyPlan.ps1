function Invoke-PocketRomCopyPlan {
<#
.SYNOPSIS
    Executes a ROM copy plan from New-PocketRomCopyPlan.

.DESCRIPTION
    Copies each planned file to its destination. Existing files are skipped unless
    -Overwrite is given (never silently overwritten). Supports -DryRun. Every action
    is logged when a -Logger is supplied.

.PARAMETER Plan
    A plan object from New-PocketRomCopyPlan.

.PARAMETER DryRun
    Report actions without copying.

.PARAMETER Overwrite
    Overwrite destination files that already exist.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Plan,

        [switch] $DryRun,

        [switch] $Overwrite,

        [switch] $SkipSpaceCheck,

        [psobject] $Logger
    )

    process {
        if (-not $DryRun -and $Plan.FileCount -gt 0 -and $Plan.Root) {
            Assert-PocketFreeSpace -Root $Plan.Root -RequiredBytes ([int64]$Plan.TotalBytes) `
                -Label "$($Plan.SystemId) ROMs" -Skip:$SkipSpaceCheck
        }
        $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

        $copied  = [System.Collections.Generic.List[string]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()
        $skippedProblems = [System.Collections.Generic.List[object]]::new()
        $skippedDuplicates = [System.Collections.Generic.List[object]]::new()
        $failed  = [System.Collections.Generic.List[object]]::new()

        if (-not $DryRun -and ($Plan.CopyableCount ?? $Plan.FileCount) -gt 0) {
            New-Item -ItemType Directory -Path $Plan.Destination -Force | Out-Null
        }

        foreach ($item in $Plan.Items) {
            # Skip problematic items (invalid FAT name, too-long path, duplicate
            # destination) rather than fail mid-copy or silently overwrite.
            if ($item.PSObject.Properties['Problem'] -and $item.Problem) {
                $skippedProblems.Add([pscustomobject]@{ RelativePath = $item.RelativePath; Reason = $item.Problem })
                & $log "SKIP (problem: $($item.Problem)) $($item.RelativePath)" 'WARN'
                continue
            }

            # Skip de-duplicated items (same name or byte-identical to a file already
            # planned) so the same ROM lands on the card only once.
            if ($item.PSObject.Properties['Duplicate'] -and $item.Duplicate) {
                $skippedDuplicates.Add([pscustomobject]@{ RelativePath = $item.RelativePath; Reason = $item.Duplicate })
                & $log "SKIP (duplicate: $($item.Duplicate)) $($item.RelativePath)" 'INFO'
                continue
            }

            $exists = Test-Path -LiteralPath $item.Destination -PathType Leaf
            if ($exists -and -not $Overwrite) {
                $skipped.Add($item.Destination)
                & $log "SKIP (exists) $($item.RelativePath)" 'INFO'
                continue
            }

            if ($DryRun) {
                $copied.Add($item.Destination)
                & $log "DRYRUN would copy $($item.RelativePath) -> $($item.Destination)" 'INFO'
                continue
            }

            try {
                $destDir = Split-Path -Parent $item.Destination
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Force:$Overwrite
                # Verify the copy landed at the right size (catches truncation / a card
                # pulled mid-write) before reporting success.
                $srcLen = (Get-Item -LiteralPath $item.Source).Length
                $dstLen = (Get-Item -LiteralPath $item.Destination -ErrorAction SilentlyContinue).Length
                if ($dstLen -ne $srcLen) {
                    throw "size mismatch after copy (expected $srcLen bytes, got $dstLen)"
                }
                $copied.Add($item.Destination)
                & $log "COPIED $($item.RelativePath)" 'INFO'
            } catch {
                $failed.Add([pscustomobject]@{ Source = $item.Source; Error = "$_" })
                & $log "FAILED $($item.RelativePath): $_" 'ERROR'
            }
        }

        [pscustomobject]@{
            PSTypeName    = 'PocketPrep.RomCopyResult'
            SystemId      = $Plan.SystemId
            Destination   = $Plan.Destination
            DryRun        = [bool]$DryRun
            CopiedCount   = $copied.Count
            SkippedCount  = $skipped.Count
            SkippedProblemCount = $skippedProblems.Count
            SkippedDuplicateCount = $skippedDuplicates.Count
            FailedCount   = $failed.Count
            Copied        = $copied.ToArray()
            Skipped       = $skipped.ToArray()
            SkippedProblems = $skippedProblems.ToArray()
            SkippedDuplicates = $skippedDuplicates.ToArray()
            Failed        = $failed.ToArray()
        }
    }
}
