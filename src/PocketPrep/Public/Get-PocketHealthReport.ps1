function Get-PocketHealthReport {
<#
.SYNOPSIS
    One-click read-only health check of the whole card.

.DESCRIPTION
    Audits the card and returns pass/info/warn/fail per category, each with the in-app fix:
      - firmware present at the root,
      - core integrity (required openFPGA definition files present and parseable),
      - required files / BIOS declared by cores or systems but missing,
      - ROM DIRECTORIES that exceed the per-folder game limit (~1300; every directory is
        counted separately, including organizer buckets and the favourites folder, because
        the device limit applies per directory),
      - overlong ROM filenames,
      - ROMs for platforms no installed core provides,
      - unmanaged cores (not in the catalog, so they won't auto-update),
      - low free space,
      - leftover empty/temp folders.
    Strictly read-only - nothing on the card is modified.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER SystemsManifest
    Path to manifests/systems.json.

.PARAMETER CoresManifest
    Path to manifests/cores.json.

.PARAMETER MaxPerFolder
    Per-directory game-count threshold (default 1300, the community ceiling).

.PARAMETER MaxNameLength
    Filename-length warning threshold (default 100 characters).

.PARAMETER MinFreeBytes
    Free-space warning threshold (default 1 GB).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $SystemsManifest,

        [Parameter(Mandatory, Position = 2)]
        [string] $CoresManifest,

        [int] $MaxPerFolder = 1300,

        [int] $MaxNameLength = 100,

        [long] $MinFreeBytes = 1GB
    )

    $checks = [System.Collections.Generic.List[object]]::new()
    $add = { param($name, $status, $detail, $fix = '')
        $checks.Add([pscustomobject]@{ Name = $name; Status = $status; Detail = $detail; Fix = $fix }) }

    $summary = Get-PocketCardSummary -Root $Root -SystemsManifest $SystemsManifest

    # 1. Firmware at the root.
    if ($summary.Firmware.Present) {
        & $add 'Firmware' 'ok' "v$($summary.Firmware.Version) ($($summary.Firmware.FileName))"
    } else {
        & $add 'Firmware' 'warn' 'No firmware .bin at the card root - the Pocket will not boot from this card.' 'Run the Firmware step.'
    }

    # 2. Core integrity.
    $integ = @(Test-PocketCoreIntegrity -Root $Root)
    $broken = @($integ | Where-Object { -not $_.Ok })
    if ($integ.Count -eq 0) {
        & $add 'Core integrity' 'info' 'No cores installed yet.' 'Install cores on the Cores step.'
    } elseif ($broken.Count -gt 0) {
        & $add 'Core integrity' 'fail' "$($broken.Count) core(s) incomplete: $(($broken | ForEach-Object { $_.Identifier }) -join ', ')." 'Use Repair on the Cores step.'
    } else {
        & $add 'Core integrity' 'ok' "All $($integ.Count) installed core(s) intact."
    }

    # 3. Required files / BIOS (data.json-declared union manifest-declared, de-duped).
    # Manifest-declared BIOS only matters when the platform is actually IN USE (ROMs on the
    # card) - a card with no Neo Geo content shouldn't warn about neogeo.zip.
    $reqMissing = @($summary.RequiredFiles | Where-Object { -not $_.Satisfied })
    $coveredPlats = @($reqMissing | ForEach-Object { ([string]$_.PlatformId).ToLowerInvariant() })
    $platsInUse = @($summary.Roms.Systems | ForEach-Object { ([string]$_.PlatformId).ToLowerInvariant() })
    $biosMissing = @($summary.Bios | Where-Object {
        (-not $_.Satisfied) -and
        ($coveredPlats -notcontains ([string]$_.PlatformId).ToLowerInvariant()) -and
        ($platsInUse -contains ([string]$_.PlatformId).ToLowerInvariant())
    })
    if ($reqMissing.Count -eq 0 -and $biosMissing.Count -eq 0) {
        & $add 'BIOS / required files' 'ok' 'Every installed core has its declared required files.'
    } else {
        $parts = @($reqMissing | ForEach-Object { "$($_.Identifier) needs $($_.Missing -join ', ')" }) +
                 @($biosMissing | ForEach-Object { "$($_.DisplayName) needs $($_.Missing -join ', ')" })
        & $add 'BIOS / required files' 'warn' ($parts -join '; ') 'Use Install BIOS on the card overview (supply your own file - never downloaded).'
    }

    # 4. Per-directory ROM counts (the device limit applies per directory).
    $overfull = [System.Collections.Generic.List[string]]::new()
    $longNames = 0
    $assetsDir = Join-Path $Root 'Assets'
    if (Test-Path -LiteralPath $assetsDir -PathType Container) {
        foreach ($pdir in Get-ChildItem -LiteralPath $assetsDir -Directory -ErrorAction SilentlyContinue) {
            $dirs = @($pdir) + @(Get-ChildItem -LiteralPath $pdir.FullName -Directory -Recurse -ErrorAction SilentlyContinue)
            foreach ($d in $dirs) {
                $files = @(Get-ChildItem -LiteralPath $d.FullName -File -ErrorAction SilentlyContinue)
                if ($files.Count -gt $MaxPerFolder) { $overfull.Add("$($d.FullName) ($($files.Count) files)") }
                $longNames += @($files | Where-Object { $_.Name.Length -gt $MaxNameLength }).Count
            }
        }
    }
    if ($overfull.Count -gt 0) {
        & $add 'Per-folder game limit' 'warn' "$($overfull.Count) folder(s) exceed $MaxPerFolder files: $($overfull -join '; '). Cores may not list every game." 'Run the Library Organizer (split into subfolders).'
    } else {
        & $add 'Per-folder game limit' 'ok' "No folder exceeds $MaxPerFolder files."
    }

    # 5. Overlong filenames.
    if ($longNames -gt 0) {
        & $add 'Filename length' 'warn' "$longNames file(s) have names longer than $MaxNameLength characters." 'Use the Library Organizer with "Shorten overlong filenames".'
    } else {
        & $add 'Filename length' 'ok' "No filenames longer than $MaxNameLength characters."
    }

    # 6-7, 9. Cleanup-scan findings (orphans, unmanaged cores, empty/temp leftovers).
    $cleanup = Get-PocketCardCleanup -Root $Root -CoresManifest $CoresManifest
    $orphans = @($cleanup.OrphanAssetPlatforms)
    if ($orphans.Count -gt 0) {
        & $add 'ROMs without a core' 'warn' ("ROMs exist for platform(s) no installed core provides: " + (($orphans | ForEach-Object { "$($_.PlatformId) ($($_.FileCount))" }) -join ', ') + ". They will not load.") 'Install the matching core(s) on the Cores step.'
    } else {
        & $add 'ROMs without a core' 'ok' 'Every ROM platform has an installed core.'
    }
    if (@($cleanup.UnmanagedCores).Count -gt 0) {
        & $add 'Unmanaged cores' 'info' ("Not in the catalog (won't auto-update): " + ($cleanup.UnmanagedCores -join ', ') + '.')
    } else {
        & $add 'Unmanaged cores' 'ok' 'All installed cores are catalog-managed.'
    }
    if ($cleanup.RemovableDirCount -gt 0) {
        & $add 'Leftover folders' 'info' "$($cleanup.RemovableDirCount) empty/temp folder(s) can be removed." 'Use Maintenance & cleanup on the card overview.'
    } else {
        & $add 'Leftover folders' 'ok' 'No empty or temp folders.'
    }

    # 8. Free space.
    $space = Get-PocketDiskSpace -Path $Root
    if ($null -ne $space.FreeBytes -and $space.FreeBytes -lt $MinFreeBytes) {
        & $add 'Free space' 'warn' ("Only {0:N1} MB free." -f ($space.FreeBytes / 1MB)) 'Free space (cleanup, region de-dupe quarantine) before adding more.'
    } elseif ($null -ne $space.FreeBytes) {
        & $add 'Free space' 'ok' ("{0:N1} GB free of {1:N1} GB." -f ($space.FreeBytes / 1GB), ($space.TotalBytes / 1GB))
    } else {
        & $add 'Free space' 'info' 'Could not determine free space for this path.'
    }

    $rank = @{ ok = 0; info = 1; warn = 2; fail = 3 }
    $overall = 'ok'
    foreach ($c in $checks) { if ($rank[$c.Status] -gt $rank[$overall]) { $overall = $c.Status } }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.HealthReport'
        Overall    = $overall
        Checks     = $checks.ToArray()
        WarnCount  = @($checks | Where-Object Status -eq 'warn').Count
        FailCount  = @($checks | Where-Object Status -eq 'fail').Count
    }
}
