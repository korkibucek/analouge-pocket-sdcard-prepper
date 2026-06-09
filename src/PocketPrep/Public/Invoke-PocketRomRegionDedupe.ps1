function Invoke-PocketRomRegionDedupe {
<#
.SYNOPSIS
    Quarantines region-duplicate ROMs recommended for removal (reversible; never deletes).

.DESCRIPTION
    Runs Get-PocketRomRegionDuplicate and MOVES each file recommended for removal out of the
    game folder into pocketprep/quarantine/<platformId>/ - which lives outside Assets, so the
    Pocket never sees it. Nothing is deleted: the kept (preferred-region) copy stays in place,
    and quarantined files can be restored by moving them back (or deleted manually once you're
    happy). Supports -DryRun.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform to de-duplicate.

.PARAMETER RegionOrder
    Priority order over USA, EU, JPN, Global (earlier = preferred).

.PARAMETER DryRun
    Report what would be quarantined without moving anything.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Moves (never deletes) to a reversible quarantine; -DryRun previews.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [string[]] $RegionOrder = @('USA', 'EU', 'JPN', 'Global'),

        [switch] $DryRun,

        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }
    $report = Get-PocketRomRegionDuplicate -Root $Root -PlatformId $PlatformId -RegionOrder $RegionOrder

    $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'
    $commonFull = if (Test-Path -LiteralPath $common) { (Resolve-Path -LiteralPath $common).Path } else { $common }
    $quarantine = Join-Path (Join-Path (Join-Path $Root 'pocketprep') 'quarantine') $PlatformId

    # Index sources by leaf name (excluding reserved folders).
    $byName = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue)) {
        if (Test-PocketReservedRomPath -Common $commonFull -FullPath $f.FullName) { continue }
        if (-not $byName.ContainsKey($f.Name)) { $byName[$f.Name] = $f.FullName }
    }

    $moved = [System.Collections.Generic.List[object]]::new()
    $failed = [System.Collections.Generic.List[object]]::new()
    foreach ($set in @($report.Sets)) {
        foreach ($rm in @($set.Remove)) {
            $src = $byName[$rm.Name]
            if (-not $src) { continue }
            $dest = Join-Path $quarantine $rm.Name
            if ($DryRun) { $moved.Add([pscustomobject]@{ From = $src; To = $dest }); continue }
            try {
                if (-not (Test-Path -LiteralPath $quarantine)) { New-Item -ItemType Directory -Path $quarantine -Force | Out-Null }
                # Don't clobber a previously-quarantined file of the same name.
                if (Test-Path -LiteralPath $dest) {
                    $bn = [System.IO.Path]::GetFileNameWithoutExtension($rm.Name); $ext = [System.IO.Path]::GetExtension($rm.Name); $n = 2
                    do { $dest = Join-Path $quarantine "$bn~$n$ext"; $n++ } while (Test-Path -LiteralPath $dest)
                }
                $srcLen = (Get-Item -LiteralPath $src).Length
                Move-Item -LiteralPath $src -Destination $dest
                if ((Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue).Length -ne $srcLen) { throw "size mismatch after move" }
                $moved.Add([pscustomobject]@{ From = $src; To = $dest })
                & $log "DEDUPE quarantined $($rm.Name)" 'INFO'
            } catch {
                $failed.Add([pscustomobject]@{ Name = $rm.Name; Error = "$_" })
                & $log "DEDUPE FAILED $($rm.Name): $_" 'ERROR'
            }
        }
    }

    [pscustomobject]@{
        PSTypeName    = 'PocketPrep.RegionDedupeResult'
        PlatformId    = $PlatformId
        RegionOrder   = $report.RegionOrder
        SetCount      = @($report.Sets).Count
        MovedCount    = $moved.Count
        FailedCount   = $failed.Count
        QuarantineDir = $quarantine
        Moved         = $moved.ToArray()
        Failed        = $failed.ToArray()
        DryRun        = [bool]$DryRun
    }
}
