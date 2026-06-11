# Pure REST dispatcher. Maps (method, path, body, state) to a { Status; Body } result
# with no sockets involved, so the entire API surface is unit-testable. The HttpListener
# wrapper (Start-PocketPrepServer) is a thin layer over this.

function Invoke-PocketApiRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [psobject] $Body,
        [Parameter(Mandatory)] [hashtable] $State
    )

    $target = [pscustomobject]@{ Root = $State.Root; IsTestMode = [bool]$State.IsTestMode }
    $key = "$($Method.ToUpperInvariant()) $Path"

    # Resolve a ROM target by id: a manifest system first, else a platform declared by an
    # installed core (#128) so ROM import works for any installed core, not just the built-ins.
    $resolveRomTarget = {
        param($id, $allowCustom)
        if (-not $id) { return $null }
        # Fast path: a built-in system (Get-PocketSystem throws on an unknown id).
        $s = try { Get-PocketSystem -Path $State.SystemsManifest -Id ([string]$id) } catch { $null }
        if ($s) { return $s }
        # Any known platform: installed-core OR catalog (#140), so ROM upload covers every core.
        $hit = @(Get-PocketKnownPlatform -SystemsManifest $State.SystemsManifest -CoresManifest $State.CoresManifest -Root $State.Root) |
            Where-Object { $_.Id -eq [string]$id } | Select-Object -First 1
        if ($hit) { return $hit }
        # Custom free-text platform-id: copy any file to Assets/<id>/common (caller opted in).
        if ($allowCustom) {
            return [pscustomobject]@{ Id = [string]$id; PlatformId = [string]$id; SupportedExtensions = @('*'); DisplayName = [string]$id; Experimental = $true }
        }
        return $null
    }

    try {
        switch -Regex ($key) {
            '^GET /api/health$' {
                return @{ Status = 200; Body = @{
                    ok = $true; product = 'Analogue Pocket SD Card Prepper'
                    root = $State.Root; testMode = [bool]$State.IsTestMode; dryRun = [bool]$State.DryRun
                    targetReady = [bool]$State.TargetReady
                } }
            }
            '^POST /api/target$' {
                if ($Body.testMode) {
                    $rp = [string]$Body.rootPath
                    if (-not $rp) { return @{ Status = 400; Body = @{ error = 'Missing rootPath for test mode.' } } }
                    if (-not (Test-Path -LiteralPath $rp)) { New-Item -ItemType Directory -Path $rp -Force | Out-Null }
                    $State.Root = (Resolve-Path -LiteralPath $rp).Path
                    $State.IsTestMode = $true; $State.TargetReady = $true
                    return @{ Status = 200; Body = @{ root = $State.Root; isTestMode = $true; ready = $true } }
                }
                if (-not $Body.drive) { return @{ Status = 400; Body = @{ error = 'Missing drive.' } } }
                $v = Test-PocketDriveSafety -Drive $Body.drive -AllowAdvancedOverride:([bool]$Body.allowOverride)
                if (-not $v.Safe) { return @{ Status = 400; Body = @{ error = 'Drive is not safe to use.'; verdict = $v } } }
                $rp = [string]$Body.drive.RootPath
                if (-not $rp) { $rp = [string]$Body.drive.DriveLetter }
                if (-not (Test-Path -LiteralPath $rp)) { return @{ Status = 400; Body = @{ error = "Target root not found: $rp" } } }
                $State.Root = (Resolve-Path -LiteralPath $rp).Path
                $State.IsTestMode = $false; $State.TargetReady = $true
                return @{ Status = 200; Body = @{ root = $State.Root; isTestMode = $false; ready = $true; verdict = $v } }
            }
            '^POST /api/eject$' {
                # Flush + best-effort unmount/eject the target so it's safe to remove. In test
                # mode (fake root on the system volume) it flushes only.
                if (-not $State.Root) { return @{ Status = 400; Body = @{ error = 'No target selected.' } } }
                $res = Dismount-PocketDrive -Root $State.Root -FlushOnly:([bool]$State.IsTestMode)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/dryrun$' {
                # Toggle dry-run at runtime so any action can be previewed without writing.
                $State.DryRun = [bool]$Body.enabled
                return @{ Status = 200; Body = @{ dryRun = [bool]$State.DryRun } }
            }
            '^GET /api/space$' {
                # Free/total bytes on the current target volume, for the UI space indicator.
                if (-not $State.Root) { return @{ Status = 200; Body = @{ ready = $false } } }
                $sp = Get-PocketDiskSpace -Path $State.Root
                return @{ Status = 200; Body = @{ ready = $true; freeBytes = $sp.FreeBytes; totalBytes = $sp.TotalBytes; usedBytes = $sp.UsedBytes } }
            }
            '^GET /api/drives$' {
                $all = if ($State.DriveProvider) {
                    Get-PocketRemovableDrive -DataProvider $State.DriveProvider -IncludeFixed
                } else {
                    Get-PocketRemovableDrive -IncludeFixed
                }
                $drives = if ($State.IncludeFixed) { @($all) } else { @($all | Where-Object IsRemovable) }
                # Fixed volumes that look like an SD card (some readers report cards as
                # fixed), so the UI can guide the user even when no removable drive is found.
                $candidates = @($all | Where-Object { (-not $_.IsRemovable) -and $_.LikelyRemovableCard })
                return @{ Status = 200; Body = @{ drives = @($drives); candidates = $candidates } }
            }
            '^POST /api/safety$' {
                if (-not $Body.drive) { return @{ Status = 400; Body = @{ error = 'Missing drive.' } } }
                $v = Test-PocketDriveSafety -Drive $Body.drive -AllowAdvancedOverride:([bool]$Body.allowOverride)
                return @{ Status = 200; Body = $v }
            }
            '^POST /api/filesystem$' {
                $v = Test-PocketFilesystem -FileSystem ([string]$Body.fileSystem)
                return @{ Status = 200; Body = $v }
            }
            '^GET /api/empty$' {
                return @{ Status = 200; Body = (Test-PocketCardEmpty -Root $State.Root) }
            }
            '^GET /api/firmware$' {
                $m = Get-PocketFirmwareManifest -Path $State.FirmwareManifest
                $r = Resolve-PocketFirmwareRelease -Manifest $m
                $age = Test-PocketFirmwareManifestAge -Manifest $m
                return @{ Status = 200; Body = @{ latest = $m.latest; release = $r; age = $age } }
            }
            '^POST /api/firmware/install$' {
                $m = Get-PocketFirmwareManifest -Path $State.FirmwareManifest
                $r = Resolve-PocketFirmwareRelease -Manifest $m -Version ([string]$Body.version)
                if ([string]$Body.mode -eq 'offline') {
                    if (-not $Body.localFile) { return @{ Status = 400; Body = @{ error = 'Offline mode needs localFile.' } } }
                    $res = Install-PocketFirmware -Root $State.Root -LocalFile ([string]$Body.localFile) -OfflineRelease $r -DryRun:([bool]$State.DryRun)
                } else {
                    $res = Install-PocketFirmware -Root $State.Root -Release $r -DryRun:([bool]$State.DryRun)
                }
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/folders$' {
                return @{ Status = 200; Body = (New-PocketFolderStructure -Root $State.Root -DryRun:([bool]$State.DryRun)) }
            }
            '^POST /api/browse$' {
                # Folder picker (read-only directory listing). POST so the client can send
                # the target path in the body.
                $p = if ($Body -and $Body.path) { [string]$Body.path } else { '' }
                return @{ Status = 200; Body = (Get-PocketDirectoryListing -Path $p) }
            }
            '^GET /api/systems$' {
                return @{ Status = 200; Body = @{ systems = @(Get-PocketSystem -Path $State.SystemsManifest) } }
            }
            '^POST /api/rom/dedupe/plan$' {
                $platId = [string]$Body.platformId
                if (-not $platId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                $order = if ($Body.regionOrder) { @($Body.regionOrder) } else { @('USA','EU','JPN','Global') }
                return @{ Status = 200; Body = (Get-PocketRomRegionDuplicate -Root $State.Root -PlatformId $platId -RegionOrder $order) }
            }
            '^POST /api/rom/dedupe$' {
                $platId = [string]$Body.platformId
                if (-not $platId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                $order = if ($Body.regionOrder) { @($Body.regionOrder) } else { @('USA','EU','JPN','Global') }
                return @{ Status = 200; Body = (Invoke-PocketRomRegionDedupe -Root $State.Root -PlatformId $platId -RegionOrder $order -DryRun:([bool]$State.DryRun)) }
            }
            '^POST /api/rom/organize/plan$' {
                $platId = [string]$Body.platformId
                if (-not $platId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                $cap = if ($Body.maxPerFolder) { [int]$Body.maxPerFolder } else { 1000 }
                $excl = @()
                try { $sys = @(Get-PocketSystem -Path $State.SystemsManifest) | Where-Object { $_.PlatformId -eq $platId } | Select-Object -First 1
                      if ($sys) { $excl = @($sys.BiosFiles) } } catch { $excl = @() }
                $maxLen = if ($Body.maxFileNameLength) { [int]$Body.maxFileNameLength } else { 100 }
                $plan = New-PocketRomOrganizePlan -Root $State.Root -PlatformId $platId -MaxPerFolder $cap -ExcludeFiles $excl `
                    -ShortenNames:([bool]$Body.shortenNames) -MaxFileNameLength $maxLen
                return @{ Status = 200; Body = $plan }
            }
            '^POST /api/rom/organize$' {
                $platId = [string]$Body.platformId
                if (-not $platId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                $cap = if ($Body.maxPerFolder) { [int]$Body.maxPerFolder } else { 1000 }
                $excl = @()
                try { $sys = @(Get-PocketSystem -Path $State.SystemsManifest) | Where-Object { $_.PlatformId -eq $platId } | Select-Object -First 1
                      if ($sys) { $excl = @($sys.BiosFiles) } } catch { $excl = @() }
                $maxLen = if ($Body.maxFileNameLength) { [int]$Body.maxFileNameLength } else { 100 }
                $plan = New-PocketRomOrganizePlan -Root $State.Root -PlatformId $platId -MaxPerFolder $cap -ExcludeFiles $excl `
                    -ShortenNames:([bool]$Body.shortenNames) -MaxFileNameLength $maxLen
                $res = Invoke-PocketRomOrganizePlan -Plan $plan -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/rom/list$' {
                # ROM leaf names under a platform's common folder (excluding the Favorites
                # folder) - feeds the favourites selector.
                $platId = [string]$Body.platformId
                if (-not $platId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                $common = Join-Path (Join-Path (Join-Path $State.Root 'Assets') $platId) 'common'
                $names = @()
                if (Test-Path -LiteralPath $common -PathType Container) {
                    $commonFull = (Resolve-Path -LiteralPath $common).Path
                    $names = @(Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue |
                        Where-Object { -not (Test-PocketReservedRomPath -Common $commonFull -FullPath $_.FullName) } |
                        ForEach-Object { $_.Name } | Sort-Object -Unique)
                }
                return @{ Status = 200; Body = @{ platformId = $platId; names = @($names); total = @($names).Count } }
            }
            '^GET /api/favorites$' {
                return @{ Status = 200; Body = (Get-PocketFavorite -Root $State.Root) }
            }
            '^POST /api/favorites$' {
                $platId = [string]$Body.platformId
                if (-not $platId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                $names = if ($Body -and $Body.names) { @($Body.names) } else { @() }
                $saved = Save-PocketFavorite -Root $State.Root -PlatformId $platId -Names $names -DryRun:([bool]$State.DryRun)
                $sync  = Sync-PocketFavorite -Root $State.Root -PlatformId $platId -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = @{ saved = $saved; sync = $sync } }
            }
            '^POST /api/favorites/sync-saves$' {
                # Re-sync save data between favourites and originals (e.g. after playing),
                # without changing which games are favourited.
                $platId = [string]$Body.platformId
                if (-not $platId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                return @{ Status = 200; Body = (Sync-PocketFavoriteSave -Root $State.Root -PlatformId $platId -DryRun:([bool]$State.DryRun)) }
            }
            '^POST /api/rom/recipes$' {
                # Fetch an arcade core's rom-recipes asset (recipe metadata only, never ROMs)
                # to pocketprep/rom-recipes/<coreId>/ on the card.
                if (-not $Body.coreId) { return @{ Status = 400; Body = @{ error = 'Missing coreId.' } } }
                if (-not (Test-Path -LiteralPath $State.CoresManifest)) { return @{ Status = 400; Body = @{ error = 'No cores manifest available.' } } }
                $res = Save-PocketRomRecipe -Root $State.Root -CoreId ([string]$Body.coreId) -CoresManifest $State.CoresManifest -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/rom/arcade-status$' {
                if (-not $Body.platformId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                return @{ Status = 200; Body = (Test-PocketArcadeRomset -Root $State.Root -PlatformId ([string]$Body.platformId)) }
            }
            '^GET /api/rom/extra-platforms$' {
                # Platforms declared by installed cores that aren't in the systems manifest.
                return @{ Status = 200; Body = @{ platforms = @(Get-PocketImportablePlatform -Root $State.Root -SystemsManifest $State.SystemsManifest) } }
            }
            '^GET /api/rom/all-platforms$' {
                # Every importable platform: built-in systems + installed cores + the catalog.
                return @{ Status = 200; Body = @{ platforms = @(Get-PocketKnownPlatform -SystemsManifest $State.SystemsManifest -CoresManifest $State.CoresManifest -Root $State.Root) } }
            }
            '^POST /api/rom/plan$' {
                $sys = & $resolveRomTarget $Body.systemId ([bool]$Body.customPlatform)
                if (-not $sys) { return @{ Status = 400; Body = @{ error = "Unknown system or platform: $($Body.systemId)" } } }
                $plan = New-PocketRomCopyPlan -System $sys -SourceFolder ([string]$Body.sourceFolder) -Root $State.Root `
                    -Recurse:([bool]$Body.recurse) -PreserveStructure:([bool]$Body.preserveStructure)
                $pidCheck = Test-PocketPlatformIdInstalled -Root $State.Root -PlatformId $sys.PlatformId
                $plan | Add-Member -NotePropertyName PlatformProvided -NotePropertyValue $pidCheck.Installed -Force
                $plan | Add-Member -NotePropertyName PlatformProvidedBy -NotePropertyValue $pidCheck.ProvidedBy -Force
                return @{ Status = 200; Body = $plan }
            }
            '^POST /api/rom/copy$' {
                # Batched copy: a client can send skip/first to transfer a large library a
                # slice at a time and advance a progress bar between calls. The plan (which
                # may hash files for dedupe) is cached per system+source so batches after
                # the first are cheap and the de-dup view stays consistent across batches.
                $sys = & $resolveRomTarget $Body.systemId ([bool]$Body.customPlatform)
                if (-not $sys) { return @{ Status = 400; Body = @{ error = "Unknown system or platform: $($Body.systemId)" } } }
                $skip  = [int]($Body.skip ?? 0)
                $first = [int]($Body.first ?? 0)
                if (-not $State.RomPlans) { $State.RomPlans = @{} }
                $cacheKey = "$($sys.Id)|$([string]$Body.sourceFolder)|$([bool]$Body.recurse)|$([bool]$Body.preserveStructure)"
                $plan = if ($skip -gt 0 -and $State.RomPlans.ContainsKey($cacheKey)) {
                    $State.RomPlans[$cacheKey]
                } else {
                    $p = New-PocketRomCopyPlan -System $sys -SourceFolder ([string]$Body.sourceFolder) -Root $State.Root `
                        -Recurse:([bool]$Body.recurse) -PreserveStructure:([bool]$Body.preserveStructure)
                    $State.RomPlans[$cacheKey] = $p
                    $p
                }
                $res = Invoke-PocketRomCopyPlan -Plan $plan -DryRun:([bool]$State.DryRun) -Overwrite:([bool]$Body.overwrite) `
                    -Skip $skip -First $first
                return @{ Status = 200; Body = $res }
            }
            '^GET /api/card-summary$' {
                # Read-only breakdown of what is already on the card (firmware/cores/ROMs +
                # whether a saved config exists), for the post-drive-select panel.
                return @{ Status = 200; Body = (Get-PocketCardSummary -Root $State.Root `
                    -SystemsManifest $State.SystemsManifest -FirmwareManifest $State.FirmwareManifest) }
            }
            '^GET /api/required-files$' {
                # Files installed cores declare as required (data.json) but are missing on the
                # card. Detect & guide only - never downloads BIOS/ROMs.
                return @{ Status = 200; Body = @{ cores = @(Get-PocketCoreRequiredFile -Root $State.Root) } }
            }
            '^POST /api/bios/install$' {
                # Place a USER-SUPPLIED BIOS into the slot a core/system declares. Only
                # declared requirements are accepted; the tool never downloads BIOS.
                foreach ($f in 'platformId', 'fileName', 'sourceFile') {
                    if (-not $Body.$f) { return @{ Status = 400; Body = @{ error = "Missing $f." } } }
                }
                $res = Install-PocketBiosFile -Root $State.Root -PlatformId ([string]$Body.platformId) `
                    -FileName ([string]$Body.fileName) -SourceFile ([string]$Body.sourceFile) `
                    -SystemsManifest $State.SystemsManifest -Overwrite:([bool]$Body.overwrite) -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^GET /api/bios-status$' {
                # Read-only: which BIOS-dependent systems (e.g. Neo Geo) have their BIOS
                # present. This tool never downloads copyrighted BIOS - it only detects/guides.
                return @{ Status = 200; Body = @{ bios = @(Get-PocketBiosStatus -Root $State.Root -SystemsManifest $State.SystemsManifest) } }
            }
            '^POST /api/images/sync$' {
                # Scrape box art for the games actually on the card (per-game, capped, cached).
                if (-not $Body.platformId) { return @{ Status = 400; Body = @{ error = 'Missing platformId.' } } }
                if (-not ($State.ImageSources -and (Test-Path -LiteralPath $State.ImageSources))) {
                    return @{ Status = 400; Body = @{ error = 'No image-sources manifest available.' } }
                }
                $res = Sync-PocketGameImage -Root $State.Root -PlatformId ([string]$Body.platformId) `
                    -ImageSources $State.ImageSources -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/images/get$' {
                # Return one cached image as a data URL (the static server only serves the
                # bundled web folder, never the card).
                if (-not $Body.platformId -or -not $Body.name) { return @{ Status = 400; Body = @{ error = 'Missing platformId or name.' } } }
                $leaf = [System.IO.Path]::GetFileName([string]$Body.name)   # no traversal
                $img = Join-Path (Join-Path (Join-Path (Join-Path $State.Root 'pocketprep') 'images') ([string]$Body.platformId)) "$leaf.png"
                if (-not (Test-Path -LiteralPath $img -PathType Leaf)) { return @{ Status = 200; Body = @{ found = $false } } }
                $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($img))
                return @{ Status = 200; Body = @{ found = $true; dataUrl = "data:image/png;base64,$b64" } }
            }
            '^POST /api/savestates/prune$' {
                # Guarded destructive op: WITHOUT confirm=true this route ALWAYS runs a
                # dry-run preview. With confirm, every deleted file is first backed up into
                # a zip under pocketprep/save-backups/ (mandatory, engine-enforced).
                $keep = [int]($Body.keepPerGame ?? 0)
                $days = [int]($Body.olderThanDays ?? 0)
                $confirmed = [bool]$Body.confirm
                $res = Invoke-PocketSaveStatePrune -Root $State.Root -KeepPerGame $keep -OlderThanDays $days `
                    -DryRun:((-not $confirmed) -or [bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^GET /api/healthcheck$' {
                # One-click read-only audit of the whole card.
                return @{ Status = 200; Body = (Get-PocketHealthReport -Root $State.Root -SystemsManifest $State.SystemsManifest -CoresManifest $State.CoresManifest) }
            }
            '^GET /api/cleanup$' {
                return @{ Status = 200; Body = (Get-PocketCardCleanup -Root $State.Root -CoresManifest $State.CoresManifest) }
            }
            '^POST /api/cleanup$' {
                # Removes only empty + temp dirs (never ROMs/saves/cores).
                return @{ Status = 200; Body = (Invoke-PocketCardCleanup -Root $State.Root -CoresManifest $State.CoresManifest -DryRun:([bool]$State.DryRun)) }
            }
            '^GET /api/profile/export$' {
                return @{ Status = 200; Body = (Export-PocketProfile -Root $State.Root -CoresManifest $State.CoresManifest) }
            }
            '^POST /api/profile/import$' {
                if (-not $Body.profile) { return @{ Status = 400; Body = @{ error = 'Missing profile.' } } }
                $res = Import-PocketProfile -Root $State.Root -ProfileData $Body.profile `
                    -CoresManifest $State.CoresManifest -SystemsManifest $State.SystemsManifest `
                    -Rescan:([bool]$Body.rescan) -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/card/onboard$' {
                # Onboard a used card: scan existing content and generate a starter config.
                return @{ Status = 200; Body = (Import-PocketUsedCard -Root $State.Root `
                    -SystemsManifest $State.SystemsManifest -FirmwareManifest $State.FirmwareManifest `
                    -DryRun:([bool]$State.DryRun)) }
            }
            '^GET /api/rom/config$' {
                # The saved source-folder -> system mapping on the card (empty if none).
                return @{ Status = 200; Body = (Get-PocketRomConfig -Root $State.Root) }
            }
            '^POST /api/rom/config$' {
                $srcs = if ($Body -and $Body.sources) { @($Body.sources) } else { @() }
                $res = Save-PocketRomConfig -Root $State.Root -Sources $srcs -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/rom/rescan$' {
                # Re-copy ROMs from every saved source (skips the wizard). Reuses the copy
                # engine, so dedupe / free-space / verify all apply.
                $res = Invoke-PocketRomRescan -Root $State.Root -SystemsManifest $State.SystemsManifest `
                    -DryRun:([bool]$State.DryRun) -Overwrite:([bool]$Body.overwrite)
                return @{ Status = 200; Body = $res }
            }
            '^GET /api/cores/integrity$' {
                return @{ Status = 200; Body = @{ cores = @(Test-PocketCoreIntegrity -Root $State.Root) } }
            }
            '^POST /api/cores/repair$' {
                if (-not (Test-Path -LiteralPath $State.CoresManifest)) { return @{ Status = 400; Body = @{ error = 'No cores manifest available.' } } }
                if (-not $Body.coreId) { return @{ Status = 400; Body = @{ error = 'Missing coreId.' } } }
                $res = Repair-PocketCore -Root $State.Root -Id ([string]$Body.coreId) -CoresManifest $State.CoresManifest -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^GET /api/installed-cores$' {
                return @{ Status = 200; Body = @{ cores = @(Get-PocketInstalledCore -Root $State.Root) } }
            }
            '^GET /api/cores/updates$' {
                if (-not (Test-Path -LiteralPath $State.CoresManifest)) { return @{ Status = 200; Body = @{ updates = @() } } }
                return @{ Status = 200; Body = @{ updates = @(Get-PocketCoreUpdateStatus -Root $State.Root -CoresManifest $State.CoresManifest) } }
            }
            '^POST /api/cores/install-all$' {
                if (-not (Test-Path -LiteralPath $State.CoresManifest)) { return @{ Status = 200; Body = @{ result = $null } } }
                $ids = if ($Body -and $Body.ids) { @($Body.ids) } else { $null }
                $res = Install-PocketCoreSet -Root $State.Root -CoresManifest $State.CoresManifest -Id $ids -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/cores/update-all$' {
                if (-not (Test-Path -LiteralPath $State.CoresManifest)) { return @{ Status = 200; Body = @{ results = @() } } }
                $res = Update-PocketCore -Root $State.Root -CoresManifest $State.CoresManifest -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = @{ results = @($res) } }
            }
            '^GET /api/cores$' {
                if (-not (Test-Path -LiteralPath $State.CoresManifest)) { return @{ Status = 200; Body = @{ cores = @() } } }
                $cores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $State.CoresManifest)
                return @{ Status = 200; Body = @{ cores = @($cores) } }
            }
            '^POST /api/cores/install-local$' {
                # Install a user-supplied core zip that is NOT in the catalog (e.g. jotego's
                # Patreon-distributed NGPC beta). Same safety as every install: openFPGA
                # structure validation, zip-slip protection, non-destructive merge.
                if (-not $Body.localZip) { return @{ Status = 400; Body = @{ error = 'Missing localZip.' } } }
                $res = Install-PocketCore -Root $State.Root -LocalZip ([string]$Body.localZip) `
                    -Overwrite:([bool]$Body.overwrite) -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/cores/image-pack$' {
                # Install platform menu images into Platforms/_images from a GitHub release
                # (owner/repo) or a local zip. User supplies the source.
                if ([string]$Body.mode -eq 'offline') {
                    if (-not $Body.localZip) { return @{ Status = 400; Body = @{ error = 'Offline mode needs localZip.' } } }
                    $res = Install-PocketImagePack -Root $State.Root -LocalZip ([string]$Body.localZip) -Overwrite:([bool]$Body.overwrite) -DryRun:([bool]$State.DryRun)
                } else {
                    if (-not $Body.owner -or -not $Body.repo) { return @{ Status = 400; Body = @{ error = 'Provide owner and repo (or a local zip).' } } }
                    $res = Install-PocketImagePack -Root $State.Root -Owner ([string]$Body.owner) -Repo ([string]$Body.repo) -Tag ([string]$Body.tag) -Overwrite:([bool]$Body.overwrite) -DryRun:([bool]$State.DryRun)
                }
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/cores/install$' {
                $core = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $State.CoresManifest) -Id ([string]$Body.coreId)
                if ([string]$Body.mode -eq 'offline') {
                    if (-not $Body.localZip) { return @{ Status = 400; Body = @{ error = 'Offline mode needs localZip.' } } }
                    $res = Install-PocketCore -Root $State.Root -LocalZip ([string]$Body.localZip) -Core $core -DryRun:([bool]$State.DryRun) -Overwrite:([bool]$Body.overwrite)
                } else {
                    $res = Install-PocketCore -Root $State.Root -Core $core -Download -DryRun:([bool]$State.DryRun) -Overwrite:([bool]$Body.overwrite)
                }
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/saves/backup$' {
                if (-not $Body.destination) { return @{ Status = 400; Body = @{ error = 'Missing destination.' } } }
                $res = Backup-PocketSaves -Root $State.Root -Destination ([string]$Body.destination) `
                    -Stamp ([string]($Body.stamp ?? 'backup')) -IncludeMemories:([bool]$Body.includeMemories) -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/saves/restore$' {
                if (-not $Body.source) { return @{ Status = 400; Body = @{ error = 'Missing source.' } } }
                $res = Restore-PocketSaves -Root $State.Root -Source ([string]$Body.source) `
                    -Overwrite:([bool]$Body.overwrite) -DryRun:([bool]$State.DryRun)
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/summary$' {
                $res = New-PocketInstallSummary -Target $target -FirmwareResult $Body.firmware `
                    -FolderResult $Body.folder -RomResults @($Body.roms) -CoreResults @($Body.cores)
                return @{ Status = 200; Body = @{ text = $res.Text; totalRomsCopied = $res.TotalRomsCopied } }
            }
            default {
                return @{ Status = 404; Body = @{ error = "No route for $key" } }
            }
        }
    } catch {
        return @{ Status = 400; Body = @{ error = "$($_.Exception.Message)" } }
    }
}
