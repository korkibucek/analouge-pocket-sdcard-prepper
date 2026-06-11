function Invoke-PocketSaveStatePrune {
<#
.SYNOPSIS
    Trims old/excess save states under Memories/Save States - backed up first, guarded.

.DESCRIPTION
    The Pocket accumulates save states under Memories/Save States. This prunes them by an
    explicit policy and is one of only two operations in the tool that delete user data
    (the other is Clear-PocketCard), so it is fenced accordingly:

      - It touches ONLY files under Memories/Save States - never Saves, ROMs, cores, or
        anything else under Memories.
      - Every file is ALWAYS backed up into a zip (pocketprep/save-backups/) before it is
        deleted - there is no way to switch the backup off, so a prune is recoverable by
        extracting the zip back over Memories/.
      - -DryRun previews the exact files; the web API forces a dry-run unless the caller
        explicitly confirms.

    Policies (both optional; a file is deleted only if it matches EVERY given policy):
      - -KeepPerGame N: keep the N newest states per game. Games are grouped by directory +
        base name with a single trailing numeric counter stripped (Game-1.sta/Game_2.sta/
        Game (3).sta/Game #4.sta belong to "Game"). A file with no numeric suffix is its own
        group, so singletons are never deleted by this policy.
      - -OlderThanDays D: only states last written more than D days ago are eligible.
    With neither policy given, nothing is eligible (the function refuses to "prune all").

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER KeepPerGame
    Keep the newest N save states per game (0 = policy not applied).

.PARAMETER OlderThanDays
    Only delete states older than this many days (0 = policy not applied).

.PARAMETER DryRun
    Report the exact files that would be deleted; delete and back up nothing.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Deliberately guarded destructive op: mandatory backup zip + -DryRun preview + confirm-gated API.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [int] $KeepPerGame = 0,

        [int] $OlderThanDays = 0,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    if ($KeepPerGame -le 0 -and $OlderThanDays -le 0) {
        throw 'Refusing to prune without a policy: give -KeepPerGame and/or -OlderThanDays.'
    }

    $statesDir = Join-Path (Join-Path $Root 'Memories') 'Save States'
    $empty = [pscustomobject]@{
        PSTypeName = 'PocketPrep.SaveStatePruneResult'
        Examined = 0; DeleteCount = 0; Deleted = @(); BackupZip = $null; DryRun = [bool]$DryRun
    }
    if (-not (Test-Path -LiteralPath $statesDir -PathType Container)) { return $empty }
    $statesFull = (Resolve-Path -LiteralPath $statesDir).Path

    $files = @(Get-ChildItem -LiteralPath $statesDir -File -Recurse -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) { return $empty }

    # Group key: directory + base name with ONE trailing numeric counter stripped
    # ("Game-1", "Game_2", "Game (3)", "Game #4" -> "game"). No suffix -> own group.
    $groupKey = {
        param($f)
        $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $stripped = $base -replace '(\s*[-_#]\s*\d+|\s*\(\d+\))$', ''
        "$($f.DirectoryName)|$($stripped.Trim().ToLowerInvariant())"
    }

    $cutoff = if ($OlderThanDays -gt 0) { (Get-Date).ToUniversalTime().AddDays(-$OlderThanDays) } else { $null }

    $toDelete = [System.Collections.Generic.List[object]]::new()
    foreach ($group in ($files | Group-Object { & $groupKey $_ })) {
        $sorted = @($group.Group | Sort-Object LastWriteTimeUtc -Descending)
        foreach ($i in 0..($sorted.Count - 1)) {
            $f = $sorted[$i]
            $excess = ($KeepPerGame -gt 0) -and ($i -ge $KeepPerGame)
            $tooOld = ($null -ne $cutoff) -and ($f.LastWriteTimeUtc -lt $cutoff)
            # A file must match EVERY active policy to be eligible.
            $eligible = $true
            if ($KeepPerGame -gt 0 -and -not $excess) { $eligible = $false }
            if ($null -ne $cutoff -and -not $tooOld)  { $eligible = $false }
            if ($eligible) { $toDelete.Add($f) }
        }
    }

    if ($toDelete.Count -eq 0) {
        $empty.Examined = $files.Count
        return $empty
    }

    $rel = { param($f) $f.FullName.Substring($statesFull.Length).TrimStart([char]'\', [char]'/') }

    $backupZip = $null
    if (-not $DryRun) {
        # MANDATORY backup before any deletion - a prune is always recoverable.
        $backupDir = Join-Path (Join-Path $Root 'pocketprep') 'save-backups'
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
        $backupZip = Join-Path $backupDir "save-states-$stamp.zip"
        $n = 2
        while (Test-Path -LiteralPath $backupZip) { $backupZip = Join-Path $backupDir "save-states-$stamp-$n.zip"; $n++ }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::Open($backupZip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in $toDelete) {
                $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, ("Save States/" + (& $rel $f)))
            }
        } finally { $zip.Dispose() }
        # Delete only after the backup zip is fully written.
        foreach ($f in $toDelete) {
            Remove-Item -LiteralPath $f.FullName -Force
            & $log "PRUNE save state $(& $rel $f)" 'WARN'
        }
        & $log "Save-state prune: deleted $($toDelete.Count) (backed up to $backupZip)" 'WARN'
    }

    [pscustomobject]@{
        PSTypeName  = 'PocketPrep.SaveStatePruneResult'
        Examined    = $files.Count
        DeleteCount = $toDelete.Count
        Deleted     = @($toDelete | ForEach-Object { & $rel $_ })
        BackupZip   = $backupZip
        DryRun      = [bool]$DryRun
    }
}
