function Invoke-PocketRomRescan {
<#
.SYNOPSIS
    Re-copies ROMs from every folder saved in the card's ROM config.

.DESCRIPTION
    Reads the saved source mapping (Get-PocketRomConfig) and, for each source, plans and
    copies its ROMs to the card using the normal copy engine - so de-duplication,
    free-space checks, post-copy size verification and skip-existing all apply. This is the
    "I added some games, sync the card" path that bypasses the full wizard.

    Sources whose folder no longer exists are reported (Missing) and skipped rather than
    failing the whole rescan. Returns one copy result per scanned source.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER SystemsManifest
    Path to the systems manifest (manifests/systems.json) used to resolve each systemId.

.PARAMETER DryRun
    Plan and report without copying.

.PARAMETER Overwrite
    Overwrite existing destination files (default: skip files already on the card).

.PARAMETER OnProgress
    Optional scriptblock forwarded to Invoke-PocketRomCopyPlan for per-file progress.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $SystemsManifest,

        [switch] $DryRun,

        [switch] $Overwrite,

        [scriptblock] $OnProgress,

        [psobject] $Logger
    )

    $config = Get-PocketRomConfig -Root $Root
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($src in @($config.Sources)) {
        if (-not (Test-Path -LiteralPath $src.Path -PathType Container)) {
            $results.Add([pscustomobject]@{
                PSTypeName = 'PocketPrep.RomRescanResult'
                SystemId   = $src.SystemId
                Source     = $src.Path
                Missing    = $true
                CopiedCount = 0; SkippedCount = 0; SkippedDuplicateCount = 0; FailedCount = 0
            })
            continue
        }

        $sys = Get-PocketSystem -Path $SystemsManifest -Id $src.SystemId
        if (-not $sys) {
            Write-Warning "Saved source references unknown system '$($src.SystemId)' - skipping."
            continue
        }

        $plan = New-PocketRomCopyPlan -System $sys -SourceFolder $src.Path -Root $Root -Recurse:$src.Recurse
        $res  = Invoke-PocketRomCopyPlan -Plan $plan -DryRun:$DryRun -Overwrite:$Overwrite `
            -OnProgress $OnProgress -Logger $Logger
        $res | Add-Member -NotePropertyName Source  -NotePropertyValue $src.Path -Force
        $res | Add-Member -NotePropertyName Missing -NotePropertyValue $false -Force
        $results.Add($res)
    }

    [pscustomobject]@{
        PSTypeName  = 'PocketPrep.RomRescanSummary'
        SourceCount = @($config.Sources).Count
        Results     = $results.ToArray()
        TotalCopied = (@($results | Measure-Object -Property CopiedCount -Sum).Sum) ?? 0
        DryRun      = [bool]$DryRun
    }
}
