function Get-PocketCardCleanup {
<#
.SYNOPSIS
    Reports leftovers on a card: unmanaged cores, orphan asset folders, empty dirs, temp dirs.

.DESCRIPTION
    Read-only maintenance scan. Categorises:
      - UnmanagedCores: installed cores not in the catalog (can't be auto-updated; informational).
      - OrphanAssetPlatforms: Assets/<platformId> folders no installed core provides a platform
        for (their ROMs won't load until you install a matching core) - INFORMATIONAL ONLY,
        because they may contain your ROMs; this tool never deletes them.
      - EmptyDirs: empty sub-folders (safe to remove).
      - ProbeDirs: the tool's own leftover ".pp-symlink-probe-*" temp folders (safe to remove).
      - SaveStateCount: number of save-state files under Memories (informational; pruning saves
        is destructive and out of scope here).
    Nothing is removed here - see Invoke-PocketCardCleanup, which only removes the safe
    categories (empty + temp dirs) and never a ROM or save.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER CoresManifest
    Optional path to manifests/cores.json (to classify installed cores as managed/unmanaged).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [string] $CoresManifest
    )

    # Installed cores vs catalog.
    $installed = @(Get-PocketInstalledCore -Root $Root)
    $catalogIds = @{}
    if ($CoresManifest -and (Test-Path -LiteralPath $CoresManifest -PathType Leaf)) {
        try { foreach ($c in @(Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest))) { $catalogIds[$c.Identifier.ToLowerInvariant()] = $true } }
        catch { Write-Warning "Could not read cores catalog: $_" }
    }
    $unmanaged = @($installed | Where-Object { -not $catalogIds.ContainsKey($_.Identifier.ToLowerInvariant()) } | ForEach-Object { $_.Identifier })

    # Platforms an installed core provides.
    $providedPlatforms = @{}
    foreach ($c in $installed) { foreach ($p in @($c.PlatformIds)) { if ($p) { $providedPlatforms[([string]$p).ToLowerInvariant()] = $true } } }

    # Orphan Assets/<platform> folders (informational - may hold ROMs, never auto-removed).
    $assetsDir = Join-Path $Root 'Assets'
    $orphans = if (Test-Path -LiteralPath $assetsDir -PathType Container) {
        foreach ($pdir in Get-ChildItem -LiteralPath $assetsDir -Directory -ErrorAction SilentlyContinue) {
            if ($providedPlatforms.ContainsKey($pdir.Name.ToLowerInvariant())) { continue }
            $files = @(Get-ChildItem -LiteralPath $pdir.FullName -File -Recurse -ErrorAction SilentlyContinue)
            [pscustomobject]@{ PlatformId = $pdir.Name; FileCount = $files.Count; SizeBytes = (@($files | Measure-Object Length -Sum).Sum) ?? 0 }
        }
    }
    $orphans = @($orphans)

    # Empty sub-directories (safe) and the tool's leftover probe dirs (safe).
    $emptyDirs = [System.Collections.Generic.List[string]]::new()
    $probeDirs = [System.Collections.Generic.List[string]]::new()
    $rootFull = (Resolve-Path -LiteralPath $Root).Path
    foreach ($d in @(Get-ChildItem -LiteralPath $Root -Directory -Recurse -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name -like '.pp-symlink-probe-*') { $probeDirs.Add($d.FullName); continue }
        # Don't list top-level structural folders even if empty.
        $rel = $d.FullName.Substring($rootFull.Length).TrimStart([char]'\', [char]'/')
        if ($rel.IndexOfAny([char[]]('\','/')) -lt 0) { continue }   # depth 1 (top-level) - keep
        if (-not (Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue)) { $emptyDirs.Add($d.FullName) }
    }

    # Save-state count under Memories (informational).
    $memDir = Join-Path $Root 'Memories'
    $saveStates = if (Test-Path -LiteralPath $memDir -PathType Container) { @(Get-ChildItem -LiteralPath $memDir -File -Recurse -ErrorAction SilentlyContinue).Count } else { 0 }

    [pscustomobject]@{
        PSTypeName           = 'PocketPrep.CardCleanup'
        UnmanagedCores       = $unmanaged
        OrphanAssetPlatforms = $orphans
        EmptyDirs            = $emptyDirs.ToArray()
        ProbeDirs            = $probeDirs.ToArray()
        SaveStateCount       = $saveStates
        RemovableDirCount    = ($emptyDirs.Count + $probeDirs.Count)
    }
}
