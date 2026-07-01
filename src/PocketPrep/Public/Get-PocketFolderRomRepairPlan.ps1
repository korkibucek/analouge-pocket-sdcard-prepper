function Get-PocketFolderRomRepairPlan {
<#
.SYNOPSIS
    Plans (does not apply) repairs for a folder-format system's game folders - the
    Neo Geo "fix-up" that resolves the core's "Missing '<NAME>' ID [n]" launch error.

.DESCRIPTION
    Pure, read-only. For a romFormat=folder system (e.g. Neo Geo), a game only boots when
    its folder under Assets/<platformId>/common/ is named exactly the core's data_path
    (e.g. mslug4) and contains the slot files that game's instance JSON references. This
    scans every game folder and classifies it:

      - Ok        : name matches a known data_path AND all required slot files are present.
      - Rename    : folder maps to exactly one known game by normalised title/data_path
                    (e.g. "Metal Slug 4" -> "mslug4") - safe to rename.
      - Attention : correctly named but missing slot files ('missing'); or a folder that
                    can't be matched to any game the core knows ('unknown'); or a rename
                    whose target folder already exists ('conflict'). Reported, not fixed.

    Only renames are auto-fixable (by Invoke-PocketFolderRomRepair). Missing data and
    un-converted MAME romsets are reported with guidance - the tool never converts or
    downloads ROM data.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The folder-format platform (e.g. 'ng').

.PARAMETER SystemsManifest
    Path to manifests/systems.json (to resolve the display name).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Root,
        [Parameter(Mandatory, Position = 1)] [string] $PlatformId,
        [Parameter(Position = 2)] [string] $SystemsManifest
    )

    $displayName = $PlatformId
    if ($SystemsManifest -and (Test-Path -LiteralPath $SystemsManifest -PathType Leaf)) {
        try {
            $sys = @(Get-PocketSystem -Path $SystemsManifest) | Where-Object { $_.PlatformId -eq $PlatformId } | Select-Object -First 1
            if ($sys) { $displayName = $sys.DisplayName }
        } catch { $null = $_ }
    }

    $norm = { param($s) (([string]$s).ToLowerInvariant() -replace '[^a-z0-9]', '') }
    $result = [pscustomobject]@{
        PSTypeName     = 'PocketPrep.FolderRomRepairPlan'
        PlatformId     = $PlatformId
        DisplayName    = $displayName
        CoreInstalled  = $false
        OkCount        = 0
        Renames        = @()
        Attention      = @()
        RenameCount    = 0
        AttentionCount = 0
    }

    $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'
    if (-not (Test-Path -LiteralPath $common -PathType Container)) { return $result }
    $commonFull = (Resolve-Path -LiteralPath $common).Path

    $games = @(Get-PocketInstanceGame -Root $Root -PlatformId $PlatformId)
    $result.CoreInstalled = $games.Count -gt 0

    # Lookups: exact data_path (lower) -> game; normalised title/data_path -> game(s).
    $byDataPath = @{}
    $byNorm = @{}
    foreach ($g in $games) {
        $byDataPath[$g.DataPath.ToLowerInvariant()] = $g
        foreach ($key in @((& $norm $g.Title), (& $norm $g.DataPath))) {
            if (-not $key) { continue }
            if (-not $byNorm.ContainsKey($key)) { $byNorm[$key] = [System.Collections.Generic.List[object]]::new() }
            if (-not ($byNorm[$key] | Where-Object { $_.DataPath -eq $g.DataPath })) { $byNorm[$key].Add($g) }
        }
    }

    $gameDirs = @(Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue |
        Where-Object { -not (Test-PocketReservedRomPath -Common $commonFull -FullPath $_.FullName) })

    $renames = [System.Collections.Generic.List[object]]::new()
    $attention = [System.Collections.Generic.List[object]]::new()
    $ok = 0
    foreach ($dir in $gameDirs) {
        $n = $dir.Name
        $nLower = $n.ToLowerInvariant()
        $hasZip = [bool](Get-ChildItem -LiteralPath $dir.FullName -File -Filter '*.zip' -ErrorAction SilentlyContinue | Select-Object -First 1)

        if ($byDataPath.ContainsKey($nLower)) {
            # Correctly named. Complete?
            $g = $byDataPath[$nLower]
            $missing = @($g.MissingFiles)
            if ($missing.Count -gt 0) {
                $detail = "missing $($missing -join ', ')" + $(if ($hasZip) { ' (folder contains a .zip - looks like a MAME romset; convert to DarkSoft format first)' } else { '' })
                $attention.Add([pscustomobject]@{ Folder = $n; Kind = 'missing'; Detail = $detail; Missing = $missing })
            } else {
                $ok++
            }
            continue
        }

        # Not a known data_path - try to identify the game.
        $key = (& $norm $n)
        $cands = if ($key -and $byNorm.ContainsKey($key)) { @($byNorm[$key]) } else { @() }
        if ($cands.Count -eq 1) {
            $to = $cands[0].DataPath
            $targetExists = (Test-Path -LiteralPath (Join-Path $common $to) -PathType Container)
            if ($targetExists) {
                $attention.Add([pscustomobject]@{ Folder = $n; Kind = 'conflict'; Detail = "would rename to '$to', but a folder named '$to' already exists"; Missing = @() })
            } else {
                $renames.Add([pscustomobject]@{ From = $n; To = $to; Title = $cands[0].Title })
            }
        } else {
            $detail = if ($cands.Count -gt 1) { "matches more than one known game - rename manually" } else { "matches no game this core knows" + $(if ($hasZip) { '; contains a .zip (a MAME romset will not work - convert to DarkSoft format)' } else { '' }) }
            $attention.Add([pscustomobject]@{ Folder = $n; Kind = 'unknown'; Detail = $detail; Missing = @() })
        }
    }

    $result.OkCount = $ok
    $result.Renames = $renames.ToArray()
    $result.Attention = $attention.ToArray()
    $result.RenameCount = $renames.Count
    $result.AttentionCount = $attention.Count
    $result
}
