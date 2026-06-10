function Sync-PocketFavoriteSave {
<#
.SYNOPSIS
    Keeps save data in sync between a favourited ROM and its original (original = master).

.DESCRIPTION
    The Pocket keys saves by the ROM's LAUNCH PATH, and the Saves tree mirrors the Assets
    tree - so the original (Assets/<plat>/common/<sub>/Game.gb) and its favourite
    (Assets/<plat>/common/!Favorites/Game.gb) each get their OWN save file, and progress
    made on one doesn't carry to the other (even when the favourite ROM is a symlink,
    because it's the save *path* that differs).

    This reconciles the two save locations for every favourited game, treating the
    ORIGINAL's save location as the master/canonical store:
      - Where the filesystem supports symlinks: the favourite's save becomes a SYMLINK to
        the original's save file, so there is one real file and they can never diverge.
      - On FAT32/exFAT (the real card): NEWEST-WINS two-way copy, with the original
        canonical on a tie. The side about to be overwritten is backed up first to
        pocketprep/save-backups/<platformId>/, so no progress is ever silently lost.
      - A favourite save with no original counterpart seeds the original (master) first.
      - A save left in !Favorites for a game that is NO LONGER favourited is folded back
        into the original (newest-wins, backup first) and then removed.

    Writes happen only inside the two mirrored Saves locations and the backup folder.
    Supports -DryRun.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform to sync.

.PARAMETER NoSymlink
    Force the copy strategy even where symlinks are supported.

.PARAMETER DryRun
    Report actions without writing anything.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Newest-wins reconcile with backup-before-overwrite; -DryRun previews.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [switch] $NoSymlink,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }
    $favFolder = Get-PocketFavoritesFolderName

    $assetsCommon = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'
    $savesCommon  = Join-Path (Join-Path (Join-Path $Root 'Saves') $PlatformId) 'common'
    $favSaveDir   = Join-Path $savesCommon $favFolder
    $backupDir    = Join-Path (Join-Path (Join-Path $Root 'pocketprep') 'save-backups') $PlatformId

    $linked = 0; $toFavorite = 0; $toOriginal = 0; $folded = 0; $backedUp = 0
    $actions = [System.Collections.Generic.List[string]]::new()

    # Back up a file (before it is overwritten or removed); never clobbers older backups.
    $backup = {
        param($file)
        if ($DryRun) { return }
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $dest = Join-Path $backupDir (Split-Path -Leaf $file)
        if (Test-Path -LiteralPath $dest) {
            $bn = [System.IO.Path]::GetFileNameWithoutExtension($dest); $ext = [System.IO.Path]::GetExtension($dest); $n = 2
            do { $dest = Join-Path $backupDir "$bn~$n$ext"; $n++ } while (Test-Path -LiteralPath $dest)
        }
        Copy-Item -LiteralPath $file -Destination $dest
    }

    # Map favourite ROM name -> the original ROM's mirrored save directory.
    $favNames = @(Get-PocketFavorite -Root $Root -PlatformId $PlatformId)
    $originDirByBase = @{}
    if (Test-Path -LiteralPath $assetsCommon -PathType Container) {
        $assetsFull = (Resolve-Path -LiteralPath $assetsCommon).Path
        foreach ($f in @(Get-ChildItem -LiteralPath $assetsCommon -File -Recurse -ErrorAction SilentlyContinue)) {
            if (Test-PocketReservedRomPath -Common $assetsFull -FullPath $f.FullName) { continue }
            $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            if ($originDirByBase.ContainsKey($base)) { continue }
            # Mirror the ROM's sub-path under common into the Saves tree.
            $relDir = $f.DirectoryName.Substring($assetsFull.Length).TrimStart([char]'\', [char]'/')
            $originDirByBase[$base] = if ($relDir) { Join-Path $savesCommon $relDir } else { $savesCommon }
        }
    }

    $useSymlink = $false
    if (-not $DryRun -and -not $NoSymlink -and $favNames.Count -gt 0) { $useSymlink = Test-PocketSymlinkSupport -Root $Root }
    $method = if ($DryRun) { 'dry-run' } elseif ($useSymlink) { 'symlink' } else { 'copy' }

    # Save files for a base name in a directory (any extension: .sav, .srm, ...).
    $savesFor = {
        param($dir, $base)
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
        @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
            Where-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -ieq $base })
    }
    $isLink = { param($p) [bool]((Get-Item -LiteralPath $p -ErrorAction SilentlyContinue).Attributes -band [System.IO.FileAttributes]::ReparsePoint) }

    # Reconcile one (originalSavePath, favouriteSavePath) pair; returns nothing, mutates counters.
    $favBaseSet = @{}
    foreach ($n in $favNames) { $favBaseSet[([System.IO.Path]::GetFileNameWithoutExtension($n)).ToLowerInvariant()] = $true }

    foreach ($name in $favNames) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $originDir = $originDirByBase[$base]
        if (-not $originDir) { continue }   # original ROM gone; leave saves alone

        # Union of save extensions present on either side.
        $exts = @(@(& $savesFor $originDir $base) + @(& $savesFor $favSaveDir $base) |
            ForEach-Object { $_.Extension.ToLowerInvariant() } | Select-Object -Unique)
        foreach ($ext in $exts) {
            $o = Join-Path $originDir "$base$ext"
            $f = Join-Path $favSaveDir "$base$ext"
            $oExists = Test-Path -LiteralPath $o -PathType Leaf
            $fExists = Test-Path -LiteralPath $f -PathType Leaf

            if ($fExists -and (& $isLink $f)) { continue }   # already a link -> in sync

            if ($fExists -and -not $oExists) {
                # Seed the master from the favourite's progress.
                $actions.Add("seed original from favourite: $base$ext")
                if (-not $DryRun) {
                    if (-not (Test-Path -LiteralPath $originDir)) { New-Item -ItemType Directory -Path $originDir -Force | Out-Null }
                    Copy-Item -LiteralPath $f -Destination $o
                }
                $toOriginal++
                $oExists = $true
            } elseif ($oExists -and $fExists) {
                $oT = (Get-Item -LiteralPath $o).LastWriteTimeUtc
                $fT = (Get-Item -LiteralPath $f).LastWriteTimeUtc
                if ($fT -gt $oT) {
                    # Favourite is newer: update the master (backup it first).
                    $actions.Add("favourite newer -> update original (backed up): $base$ext")
                    & $backup $o; $backedUp++
                    if (-not $DryRun) { Copy-Item -LiteralPath $f -Destination $o -Force }
                    $toOriginal++
                } elseif (-not $useSymlink -and $oT -gt $fT) {
                    # Original is newer: refresh the favourite copy (backup it first).
                    $actions.Add("original newer -> update favourite (backed up): $base$ext")
                    & $backup $f; $backedUp++
                    if (-not $DryRun) { Copy-Item -LiteralPath $o -Destination $f -Force }
                    $toFavorite++
                }
            }

            if (-not $oExists) { continue }   # nothing to mirror yet

            if ($useSymlink) {
                # Replace the favourite's save with a link to the master (backup any real file).
                if ($fExists -and -not (& $isLink $f)) { & $backup $f; $backedUp++; if (-not $DryRun) { Remove-Item -LiteralPath $f -Force } }
                if (-not $DryRun) {
                    if (-not (Test-Path -LiteralPath $favSaveDir)) { New-Item -ItemType Directory -Path $favSaveDir -Force | Out-Null }
                    if (-not (Test-Path -LiteralPath $f)) { New-Item -ItemType SymbolicLink -Path $f -Value $o | Out-Null }
                }
                $linked++; $actions.Add("favourite save linked to original: $base$ext")
            } elseif (-not $fExists) {
                $actions.Add("copy original save to favourite: $base$ext")
                if (-not $DryRun) {
                    if (-not (Test-Path -LiteralPath $favSaveDir)) { New-Item -ItemType Directory -Path $favSaveDir -Force | Out-Null }
                    Copy-Item -LiteralPath $o -Destination $f
                }
                $toFavorite++
            }
        }
    }

    # Fold back saves for games no longer favourited, then remove the stale mirror.
    if (Test-Path -LiteralPath $favSaveDir -PathType Container) {
        foreach ($sf in @(Get-ChildItem -LiteralPath $favSaveDir -File -ErrorAction SilentlyContinue)) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($sf.Name)
            if ($favBaseSet.ContainsKey($base.ToLowerInvariant())) { continue }
            $originDir = $originDirByBase[$base]
            if (-not $originDir) { continue }   # can't locate the original; leave the save alone
            $o = Join-Path $originDir $sf.Name
            $actions.Add("fold back unfavourited save: $($sf.Name)")
            if (-not $DryRun) {
                if (-not (& $isLink $sf.FullName)) {
                    $oNewer = (Test-Path -LiteralPath $o) -and ((Get-Item -LiteralPath $o).LastWriteTimeUtc -ge $sf.LastWriteTimeUtc)
                    if (-not $oNewer) {
                        if (Test-Path -LiteralPath $o) { & $backup $o; $backedUp++ }
                        if (-not (Test-Path -LiteralPath $originDir)) { New-Item -ItemType Directory -Path $originDir -Force | Out-Null }
                        Copy-Item -LiteralPath $sf.FullName -Destination $o -Force
                    }
                    & $backup $sf.FullName; $backedUp++
                }
                Remove-Item -LiteralPath $sf.FullName -Force
            }
            $folded++
        }
        if (-not $DryRun -and -not (Get-ChildItem -LiteralPath $favSaveDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $favSaveDir -Force -ErrorAction SilentlyContinue
        }
    }

    & $log "FAVSAVE [$PlatformId] method=$method linked=$linked toFav=$toFavorite toOrig=$toOriginal folded=$folded backups=$backedUp" 'INFO'
    [pscustomobject]@{
        PSTypeName       = 'PocketPrep.FavoriteSaveSyncResult'
        PlatformId       = $PlatformId
        Method           = $method
        LinkedCount      = $linked
        CopiedToFavorite = $toFavorite
        CopiedToOriginal = $toOriginal
        FoldedBackCount  = $folded
        BackupCount      = $backedUp
        Actions          = $actions.ToArray()
        DryRun           = [bool]$DryRun
    }
}
