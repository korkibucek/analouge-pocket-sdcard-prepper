function Get-PocketRomRegionDuplicate {
<#
.SYNOPSIS
    Finds region-variant duplicate ROMs and recommends which to keep/remove by region order.

.DESCRIPTION
    Parses No-Intro/Redump-style filenames for region tags (e.g. "(USA)", "(Europe)",
    "(Japan)", "(World)", "(USA, Europe)", PAL/NTSC/NTSC-J synonyms) and groups files that are
    the SAME title differing ONLY by region. Grouping strips only the region parentheses and
    keeps everything else (disc, revision, language), so multi-disc games and revisions are
    NOT collapsed together. For each group with more than one region variant it recommends
    keeping the highest-priority region (per RegionOrder) and lists the rest as removable.

    Recommendation only - nothing is moved or deleted here (see Invoke-PocketRomRegionDedupe).
    Region-less files are never grouped or flagged.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform whose ROMs to analyse (Assets/<PlatformId>/common).

.PARAMETER RegionOrder
    Priority order over the categories USA, EU, JPN, Global (earlier = preferred). Defaults to
    USA, EU, JPN, Global.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [string[]] $RegionOrder = @('USA', 'EU', 'JPN', 'Global')
    )

    # Normalise/validate the requested order; append any missing categories at the end.
    $valid = @('USA', 'EU', 'JPN', 'Global')
    $order = @($RegionOrder | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() } | Where-Object { $valid -contains $_ })
    foreach ($v in $valid) { if ($order -notcontains $v) { $order += $v } }

    # token (lowercased) -> region category.
    $regionMap = @{}
    foreach ($t in 'usa', 'us', 'america', 'canada', 'ntsc') { $regionMap[$t] = 'USA' }
    foreach ($t in 'europe', 'eu', 'uk', 'england', 'united kingdom', 'germany', 'france', 'spain', 'italy', 'netherlands', 'sweden', 'australia', 'pal', 'scandinavia', 'ireland', 'austria', 'belgium', 'denmark', 'finland', 'norway', 'poland', 'portugal', 'greece', 'russia', 'switzerland') { $regionMap[$t] = 'EU' }
    foreach ($t in 'japan', 'jp', 'jpn', 'ntsc-j', 'ntscj') { $regionMap[$t] = 'JPN' }
    foreach ($t in 'world', 'asia', 'korea', 'china', 'taiwan', 'hong kong', 'brazil', 'latin america', 'international') { $regionMap[$t] = 'Global' }

    $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'
    if (-not (Test-Path -LiteralPath $common -PathType Container)) {
        return [pscustomobject]@{ PSTypeName = 'PocketPrep.RegionDuplicateReport'; PlatformId = $PlatformId; RegionOrder = $order; Sets = @(); RemoveCount = 0; ReclaimBytes = 0 }
    }
    $commonFull = (Resolve-Path -LiteralPath $common).Path

    $parenRe = [regex]'\(([^)]*)\)'
    $entries = foreach ($f in @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue)) {
        if (Test-PocketReservedRomPath -Common $commonFull -FullPath $f.FullName) { continue }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $cats = [System.Collections.Generic.List[string]]::new()
        # Remove region-only parentheses to form the base title; keep all other tags.
        $base = $parenRe.Replace($stem, {
            param($m)
            $tokens = @($m.Groups[1].Value -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
            $mapped = @($tokens | ForEach-Object { $regionMap[$_] } | Where-Object { $_ })
            if ($tokens.Count -gt 0 -and $mapped.Count -eq $tokens.Count) {
                foreach ($c in $mapped) { if (-not $cats.Contains($c)) { $cats.Add($c) } }
                return ''          # all tokens were regions -> drop this paren group
            }
            return $m.Value         # keep non-region groups (disc, rev, languages)
        })
        $baseTitle = (($base -replace '\s+', ' ').Trim()).ToLowerInvariant()
        $rank = if ($cats.Count) { ($cats | ForEach-Object { $order.IndexOf($_) } | Measure-Object -Minimum).Minimum } else { $null }
        [pscustomobject]@{
            Name = $f.Name; FullName = $f.FullName; SizeBytes = $f.Length
            BaseTitle = $baseTitle; Regions = $cats.ToArray(); Rank = $rank
        }
    }
    $entries = @($entries | Where-Object { $null -ne $_.Rank })   # region-less files are never touched

    $sets = foreach ($g in ($entries | Group-Object BaseTitle)) {
        if ($g.Count -lt 2) { continue }
        $ranked = @($g.Group | Sort-Object Rank, { $_.Name.ToLowerInvariant() })
        $keep = $ranked[0]; $remove = @($ranked | Select-Object -Skip 1)
        if (-not $remove.Count) { continue }
        [pscustomobject]@{
            Title  = $g.Name
            Keep   = [pscustomobject]@{ Name = $keep.Name; Regions = $keep.Regions }
            Remove = @($remove | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Regions = $_.Regions; SizeBytes = $_.SizeBytes } })
        }
    }
    $sets = @($sets | Where-Object { $_ })
    $removeItems = @($sets | ForEach-Object { $_.Remove })

    [pscustomobject]@{
        PSTypeName   = 'PocketPrep.RegionDuplicateReport'
        PlatformId   = $PlatformId
        RegionOrder  = $order
        Sets         = $sets
        RemoveCount  = $removeItems.Count
        ReclaimBytes = (@($removeItems | Measure-Object -Property SizeBytes -Sum).Sum) ?? 0
    }
}
