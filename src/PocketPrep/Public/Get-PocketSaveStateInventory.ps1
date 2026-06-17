function Get-PocketSaveStateInventory {
<#
.SYNOPSIS
    Lists every save state ("Memory") on the card, grouped by game, for the Memory Cleaner.

.DESCRIPTION
    Read-only. Enumerates the files under Memories/Save States, groups them by game (the
    same grouping the policy prune uses), and flags the newest state in each group so the
    UI can offer a "keep newest per game" bulk selection and show the user exactly what
    would be kept vs deleted. Nothing on the card is modified.

.PARAMETER Root
    SD card root or fake SD root folder.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root
    )

    $statesDir = Join-Path (Join-Path $Root 'Memories') 'Save States'
    $empty = [pscustomobject]@{
        PSTypeName = 'PocketPrep.SaveStateInventory'
        Total = 0; TotalBytes = 0; Items = @(); Games = @()
    }
    if (-not (Test-Path -LiteralPath $statesDir -PathType Container)) { return $empty }
    $statesFull = (Resolve-Path -LiteralPath $statesDir).Path

    $files = @(Get-ChildItem -LiteralPath $statesDir -File -Recurse -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return $empty }

    $rel = { param($f) $f.FullName.Substring($statesFull.Length).TrimStart([char]'\', [char]'/').Replace('\', '/') }

    $items = [System.Collections.Generic.List[object]]::new()
    $games = [System.Collections.Generic.List[object]]::new()
    foreach ($group in ($files | Group-Object { Get-PocketSaveStateGroupKey -Directory $_.DirectoryName -Name $_.Name })) {
        # Newest first, so index 0 is the one "keep newest per game" preserves.
        $sorted = @($group.Group | Sort-Object LastWriteTimeUtc -Descending)
        # A readable game label: the stripped base name of the newest state.
        $label = ($sorted[0].BaseName -replace '(\s*[-_#]\s*\d+|\s*\(\d+\))$', '').Trim()
        $gameItems = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $sorted.Count; $i++) {
            $f = $sorted[$i]
            $item = [pscustomobject]@{
                Game            = $label
                Name            = $f.Name
                RelativePath    = (& $rel $f)
                SizeBytes       = $f.Length
                LastWriteUtc    = $f.LastWriteTimeUtc.ToString('o')
                IsLatestForGame = ($i -eq 0)
            }
            $items.Add($item)
            $gameItems.Add($item)
        }
        $games.Add([pscustomobject]@{
            Game  = $label
            Count = $gameItems.Count
            Items = $gameItems.ToArray()
        })
    }

    $ordered = @($items | Sort-Object Game, @{ Expression = 'LastWriteUtc'; Descending = $true })
    [pscustomobject]@{
        PSTypeName = 'PocketPrep.SaveStateInventory'
        Total      = $ordered.Count
        TotalBytes = [int64]((($ordered | Measure-Object -Property SizeBytes -Sum).Sum) ?? 0)
        Items      = $ordered
        Games      = @($games | Sort-Object Game)
    }
}
