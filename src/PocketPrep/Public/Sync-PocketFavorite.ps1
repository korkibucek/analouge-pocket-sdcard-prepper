function Sync-PocketFavorite {
<#
.SYNOPSIS
    Materialises a platform's Favorites folder from the saved favourites list.

.DESCRIPTION
    Ensures Assets/<platformId>/common/!Favorites contains exactly the ROMs marked as
    favourites (Save-PocketFavorite). Each favourite is found by name under common (the
    original stays put in its alphabetical/organized location) and surfaced in Favorites as
    a SYMBOLIC LINK where the filesystem supports it (Test-PocketSymlinkSupport), otherwise a
    COPY (the real FAT32/exFAT card can't do links). Stale entries inside the tool-managed
    Favorites folder are removed; everywhere else is left untouched.

    Note: on the copy path a favourite is a duplicate file with its own save data (the Pocket
    keys saves by path).

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform to sync.

.PARAMETER DryRun
    Report actions without creating/removing anything.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Operates only inside the tool-managed Favorites folder; -DryRun previews.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $favFolderName = Get-PocketFavoritesFolderName   # "!Favorites" - sorts to the top of the menu
    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $PlatformId) 'common'
    $favDir = Join-Path $common $favFolderName
    $favNames = @(Get-PocketFavorite -Root $Root -PlatformId $PlatformId)
    $wantByKey = @{}; foreach ($n in $favNames) { $wantByKey[$n.ToLowerInvariant()] = $n }

    $linked = 0; $copied = 0; $removed = 0; $missing = [System.Collections.Generic.List[string]]::new()
    $method = 'none'

    if (-not (Test-Path -LiteralPath $common -PathType Container)) {
        return [pscustomobject]@{
            PSTypeName = 'PocketPrep.FavoritesSyncResult'; PlatformId = $PlatformId; Method = $method
            LinkedCount = 0; CopiedCount = 0; RemovedCount = 0; Missing = @($favNames); DryRun = [bool]$DryRun
        }
    }

    # Migrate a legacy "Favorites" folder to "!Favorites" (so it sorts first), then continue.
    $legacy = Join-Path $common 'Favorites'
    if (-not $DryRun -and $favFolderName -ne 'Favorites' -and (Test-Path -LiteralPath $legacy -PathType Container)) {
        if (-not (Test-Path -LiteralPath $favDir)) { New-Item -ItemType Directory -Path $favDir -Force | Out-Null }
        foreach ($lf in @(Get-ChildItem -LiteralPath $legacy -File -ErrorAction SilentlyContinue)) {
            $to = Join-Path $favDir $lf.Name
            if (-not (Test-Path -LiteralPath $to)) { Move-Item -LiteralPath $lf.FullName -Destination $to -ErrorAction SilentlyContinue }
        }
        if (-not (Get-ChildItem -LiteralPath $legacy -Force -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue }
        & $log "FAV migrated legacy Favorites -> $favFolderName" 'INFO'
    }

    # Index candidate sources by leaf name, excluding the tool-managed favourites folder(s).
    $commonFull = (Resolve-Path -LiteralPath $common).Path
    $srcByKey = @{}
    foreach ($f in @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue)) {
        if (Test-PocketReservedRomPath -Common $commonFull -FullPath $f.FullName) { continue }
        $k = $f.Name.ToLowerInvariant()
        if (-not $srcByKey.ContainsKey($k)) { $srcByKey[$k] = $f.FullName }
    }

    $useSymlink = $false
    if (-not $DryRun -and $favNames.Count -gt 0) { $useSymlink = Test-PocketSymlinkSupport -Root $Root }
    $method = if ($favNames.Count -eq 0) { 'none' } elseif ($useSymlink) { 'symlink' } else { 'copy' }

    # Remove stale entries already in Favorites (only inside this tool-managed folder).
    if (Test-Path -LiteralPath $favDir -PathType Container) {
        foreach ($existing in @(Get-ChildItem -LiteralPath $favDir -File -ErrorAction SilentlyContinue)) {
            if (-not $wantByKey.ContainsKey($existing.Name.ToLowerInvariant())) {
                if (-not $DryRun) { Remove-Item -LiteralPath $existing.FullName -Force -ErrorAction SilentlyContinue }
                $removed++; & $log "FAV remove stale $($existing.Name)" 'INFO'
            }
        }
    }

    # Add each favourite that isn't already present.
    foreach ($name in $favNames) {
        $src = $srcByKey[$name.ToLowerInvariant()]
        if (-not $src) { $missing.Add($name); & $log "FAV missing source $name" 'WARN'; continue }
        $dest = Join-Path $favDir $name
        if (Test-Path -LiteralPath $dest) { continue }   # already present -> idempotent
        if ($DryRun) { if ($useSymlink) { $linked++ } else { $copied++ }; continue }
        try {
            if (-not (Test-Path -LiteralPath $favDir)) { New-Item -ItemType Directory -Path $favDir -Force | Out-Null }
            if ($useSymlink) {
                New-Item -ItemType SymbolicLink -Path $dest -Value $src -ErrorAction Stop | Out-Null
                $linked++; & $log "FAV link $name" 'INFO'
            } else {
                Copy-Item -LiteralPath $src -Destination $dest -ErrorAction Stop
                $srcLen = (Get-Item -LiteralPath $src).Length
                $dstLen = (Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue).Length
                if ($dstLen -ne $srcLen) { throw "size mismatch after copy (expected $srcLen, got $dstLen)" }
                $copied++; & $log "FAV copy $name" 'INFO'
            }
        } catch {
            $missing.Add($name); & $log "FAV FAILED $name`: $_" 'ERROR'
        }
    }

    # If there are no favourites left, drop the (now-empty) Favorites folder.
    if (-not $DryRun -and $favNames.Count -eq 0 -and (Test-Path -LiteralPath $favDir -PathType Container)) {
        if (-not (Get-ChildItem -LiteralPath $favDir -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $favDir -Force -ErrorAction SilentlyContinue
        }
    }

    [pscustomobject]@{
        PSTypeName   = 'PocketPrep.FavoritesSyncResult'
        PlatformId   = $PlatformId
        Method       = $method
        LinkedCount  = $linked
        CopiedCount  = $copied
        RemovedCount = $removed
        Missing      = $missing.ToArray()
        DryRun       = [bool]$DryRun
    }
}
