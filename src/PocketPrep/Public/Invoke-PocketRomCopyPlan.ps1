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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Plan,

        [switch] $DryRun,

        [switch] $Overwrite,

        [psobject] $Logger
    )

    process {
        $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

        $copied  = [System.Collections.Generic.List[string]]::new()
        $skipped = [System.Collections.Generic.List[string]]::new()
        $failed  = [System.Collections.Generic.List[object]]::new()

        if (-not $DryRun -and $Plan.FileCount -gt 0) {
            New-Item -ItemType Directory -Path $Plan.Destination -Force | Out-Null
        }

        foreach ($item in $Plan.Items) {
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
            FailedCount   = $failed.Count
            Copied        = $copied.ToArray()
            Skipped       = $skipped.ToArray()
            Failed        = $failed.ToArray()
        }
    }
}
