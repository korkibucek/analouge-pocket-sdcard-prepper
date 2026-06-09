BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:repo = $repo
}

Describe 'Invoke-PocketApiRoute' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_api_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:state = @{
            Root = $script:root; IsTestMode = $true; DryRun = $false
            FirmwareManifest = (Join-Path $script:repo 'manifests/firmware.json')
            SystemsManifest  = (Join-Path $script:repo 'manifests/systems.json')
            CoresManifest    = (Join-Path $script:repo 'manifests/cores.json')
        }
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'GET /api/health returns ok' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/health' -State $s }
        $r.Status | Should -Be 200
        $r.Body.ok | Should -BeTrue
    }
    It 'GET /api/drives uses an injected provider' {
        $state = $script:state.Clone()
        $state.DriveProvider = { @([pscustomobject]@{ DriveLetter='/mnt/x'; RootPath='/mnt/x'; Label='X'; FileSystem='exFAT'; SizeBytes=64GB; FreeBytes=64GB; IsRemovable=$true; BusType='USB'; MediaType='' }) }
        $r = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/drives' -State $s }
        @($r.Body.drives).Count | Should -Be 1
    }
    It 'GET /api/drives surfaces fixed likely-card candidates separately' {
        $state = $script:state.Clone()
        $state.DriveProvider = {
            @(
                [pscustomobject]@{ DriveLetter='C:'; RootPath='C:\'; Label='OS'; FileSystem='NTFS'; SizeBytes=1TB; FreeBytes=1GB; IsRemovable=$false; BusType='NVMe'; MediaType='' },
                [pscustomobject]@{ DriveLetter='G:'; RootPath='G:\'; Label='CARD'; FileSystem='exFAT'; SizeBytes=64GB; FreeBytes=64GB; IsRemovable=$false; BusType='SATA'; MediaType='' }
            )
        }
        $r = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/drives' -State $s }
        @($r.Body.drives).Count | Should -Be 0           # neither is removable, IncludeFixed off
        @($r.Body.candidates).Count | Should -Be 1       # the exFAT 64GB fixed disk
        $r.Body.candidates[0].RootPath | Should -Be 'G:\'
    }
    It 'POST /api/eject flushes (flush-only in test mode) without throwing' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/eject' -Body ([pscustomobject]@{}) -State $s }
        $r.Status | Should -Be 200
        $r.Body.Flushed | Should -BeTrue
        $r.Body.Skipped | Should -BeTrue   # test-mode state -> flush only, no eject
    }
    It 'POST /api/dryrun toggles dry-run at runtime' {
        $state = $script:state.Clone(); $state.DryRun = $false
        $on = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/dryrun' -Body ([pscustomobject]@{ enabled = $true }) -State $s }
        $on.Body.dryRun | Should -BeTrue
        $state.DryRun | Should -BeTrue
        $off = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/dryrun' -Body ([pscustomobject]@{ enabled = $false }) -State $s }
        $off.Body.dryRun | Should -BeFalse
        $state.DryRun | Should -BeFalse
    }
    It 'GET /api/space reports free/total bytes for the target volume' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/space' -State $s }
        $r.Status | Should -Be 200
        $r.Body.ready | Should -BeTrue
        $r.Body.totalBytes | Should -BeGreaterThan 0
        $r.Body.freeBytes  | Should -BeGreaterThan 0
    }
    It 'GET /api/empty reports a fresh root empty' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/empty' -State $s }
        $r.Body.IsEmpty | Should -BeTrue
    }
    It 'POST /api/folders creates the structure' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/folders' -State $s }
        $r.Body.Created | Should -Contain 'Assets'
    }
    It 'GET /api/systems returns systems' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/systems' -State $s }
        @($r.Body.systems).Count | Should -BeGreaterThan 5
    }
    It 'POST /api/rom/plan matches ROMs' {
        $src = Join-Path $script:root '_src'; New-Item -ItemType Directory $src -Force | Out-Null
        'x' | Set-Content (Join-Path $src 'g.gb')
        $body = [pscustomobject]@{ systemId='gb'; sourceFolder=$src }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/plan' -Body $b -State $s }
        $r.Body.FileCount | Should -Be 1
    }
    It 'POST /api/rom/copy honours skip/first for batched transfer' {
        $src = Join-Path $script:root '_srcbatch'; New-Item -ItemType Directory $src -Force | Out-Null
        1..4 | ForEach-Object { "rom$_" | Set-Content (Join-Path $src "g$_.gb") }
        $copied = 0
        for ($skip = 0; $skip -lt 4; $skip += 2) {
            $body = [pscustomobject]@{ systemId='gb'; sourceFolder=$src; skip=$skip; first=2 }
            $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
                Invoke-PocketApiRoute -Method POST -Path '/api/rom/copy' -Body $b -State $s }
            $r.Status | Should -Be 200
            $r.Body.ItemTotal | Should -Be 4
            $r.Body.BatchSkip | Should -Be $skip
            $copied += $r.Body.CopiedCount
        }
        $copied | Should -Be 4
        (Get-ChildItem (Join-Path $script:state.Root 'Assets/gb/common') -File).Count | Should -Be 4
    }
    It 'GET /api/card-summary breaks down firmware/cores/ROMs/config' {
        'fw' | Set-Content (Join-Path $script:root 'pocket_firmware_2_5.bin')
        $common = Join-Path $script:root 'Assets/gb/common'; New-Item -ItemType Directory $common -Force | Out-Null
        'a' | Set-Content (Join-Path $common 'one.gb')
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/card-summary' -State $s }
        $r.Status | Should -Be 200
        $r.Body.Firmware.Version | Should -Be '2.5'
        $r.Body.Roms.TotalFiles | Should -Be 1
    }
    It 'POST /api/rom/dedupe plan + apply quarantines region duplicates by preference' {
        $common = Join-Path $script:root 'Assets/gb/common'; New-Item -ItemType Directory $common -Force | Out-Null
        'a' | Set-Content (Join-Path $common 'Sonic (USA).gb'); 'b' | Set-Content (Join-Path $common 'Sonic (Europe).gb')
        $body = [pscustomobject]@{ platformId='gb'; regionOrder=@('EU','USA','JPN','Global') }
        $p = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/dedupe/plan' -Body $b -State $s }
        $p.Status | Should -Be 200
        $p.Body.RemoveCount | Should -Be 1
        $p.Body.Sets[0].Keep.Name | Should -Be 'Sonic (Europe).gb'
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/dedupe' -Body $b -State $s }
        $r.Status | Should -Be 200
        $r.Body.MovedCount | Should -Be 1
        (Test-Path (Join-Path $common 'Sonic (Europe).gb')) | Should -BeTrue   # preferred kept
        (Test-Path (Join-Path $common 'Sonic (USA).gb')) | Should -BeFalse     # quarantined
    }
    It 'POST /api/rom/organize plans and moves a large library into subfolders' {
        $common = Join-Path $script:root 'Assets/gb/common'; New-Item -ItemType Directory $common -Force | Out-Null
        1..6 | ForEach-Object { "rom$_" | Set-Content (Join-Path $common ('{0:D2}.gb' -f $_)) }
        $body = [pscustomobject]@{ platformId = 'gb'; maxPerFolder = 2 }
        $plan = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/organize/plan' -Body $b -State $s }
        $plan.Status | Should -Be 200
        $plan.Body.NeedsBuckets | Should -BeTrue
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/organize' -Body $b -State $s }
        $r.Status | Should -Be 200
        $r.Body.MovedCount | Should -Be 6
        @(Get-ChildItem -LiteralPath $common -File).Count | Should -Be 0   # all in subfolders now
    }
    It 'POST /api/rom/organize shortens overlong filenames when requested' {
        $common = Join-Path $script:root 'Assets/gb/common'; New-Item -ItemType Directory $common -Force | Out-Null
        $long = ('L' * 130) + '.gb'
        'rom' | Set-Content (Join-Path $common $long)
        $body = [pscustomobject]@{ platformId='gb'; maxPerFolder=1000; shortenNames=$true; maxFileNameLength=40 }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/organize' -Body $b -State $s }
        $r.Status | Should -Be 200
        $r.Body.RenamedCount | Should -Be 1
        (Get-ChildItem -LiteralPath $common -File)[0].Name.Length | Should -BeLessOrEqual 40
    }
    It 'GET /api/rom/all-platforms lists systems + catalog; copy works for catalog & custom platforms' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/rom/all-platforms' -State $s }
        $r.Status | Should -Be 200
        @($r.Body.platforms.PlatformId) | Should -Contain 'gb'           # system
        @($r.Body.platforms.PlatformId) | Should -Contain 'gameandwatch' # catalog-only

        # Copy to a catalog platform (core not installed) - resolves via the catalog.
        $src = Join-Path $script:root '_cat'; New-Item -ItemType Directory $src -Force | Out-Null
        'a' | Set-Content (Join-Path $src 'game.bin')
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = [pscustomobject]@{ systemId='gameandwatch'; sourceFolder=$src } } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/copy' -Body $b -State $s }
        $r.Status | Should -Be 200
        (Test-Path (Join-Path $script:state.Root 'Assets/gameandwatch/common/game.bin')) | Should -BeTrue

        # Copy to a totally custom platform-id (opt-in) - synthesised match-all target.
        $src2 = Join-Path $script:root '_custom'; New-Item -ItemType Directory $src2 -Force | Out-Null
        'b' | Set-Content (Join-Path $src2 'thing.dat')
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = [pscustomobject]@{ systemId='mycore'; sourceFolder=$src2; customPlatform=$true } } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/copy' -Body $b -State $s }
        $r.Status | Should -Be 200
        (Test-Path (Join-Path $script:state.Root 'Assets/mycore/common/thing.dat')) | Should -BeTrue

        # Without the opt-in, an unknown id is rejected.
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = [pscustomobject]@{ systemId='zzznope'; sourceFolder=$src2 } } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/copy' -Body $b -State $s }
        $r.Status | Should -Be 400
    }
    It 'GET /api/rom/extra-platforms + plan/copy work for an installed-core platform' {
        # Install a fake core that declares a platform the manifest does not know.
        $coreDir = Join-Path $script:root 'Cores/Some.WonderSwan'; New-Item -ItemType Directory $coreDir -Force | Out-Null
        @{ core = @{ metadata = @{ shortname='WS'; author='x'; version='1.0'; platform_ids=@('wonderswan') } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $coreDir 'core.json')
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/rom/extra-platforms' -State $s }
        @($r.Body.platforms.PlatformId) | Should -Contain 'wonderswan'

        # Plan + copy ROMs to that platform via its id.
        $src = Join-Path $script:root '_ws'; New-Item -ItemType Directory $src -Force | Out-Null
        'a' | Set-Content (Join-Path $src 'g.ws')
        $body = [pscustomobject]@{ systemId='wonderswan'; sourceFolder=$src }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/copy' -Body $b -State $s }
        $r.Status | Should -Be 200
        (Test-Path (Join-Path $script:state.Root 'Assets/wonderswan/common/g.ws')) | Should -BeTrue
    }
    It 'GET /api/required-files flags an installed core''s missing required file' {
        $cd = Join-Path $script:root 'Cores/Test.NeoGeo'; New-Item -ItemType Directory $cd -Force | Out-Null
        @{ core = @{ metadata = @{ shortname='NG'; author='x'; version='1'; platform_ids=@('ng') } } } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cd 'core.json')
        @{ data = @{ data_slots = @(@{ name='BIOS'; required=$true; filename='uni-bios.rom' }) } } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cd 'data.json')
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/required-files' -State $s }
        $r.Status | Should -Be 200
        ($r.Body.cores | Where-Object Identifier -eq 'Test.NeoGeo').Missing | Should -Contain 'uni-bios.rom'
    }
    It 'GET /api/bios-status flags missing Neo Geo BIOS (never downloads it)' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/bios-status' -State $s }
        $r.Status | Should -Be 200
        $ng = $r.Body.bios | Where-Object SystemId -eq 'neogeo'
        $ng.Satisfied | Should -BeFalse
    }
    It 'POST /api/rom/list + favourites round-trip and materialise a Favorites folder' {
        $common = Join-Path $script:root 'Assets/gb/common'; New-Item -ItemType Directory $common -Force | Out-Null
        'a' | Set-Content (Join-Path $common 'Tetris.gb'); 'b' | Set-Content (Join-Path $common 'Zelda.gb')
        # List ROMs for the picker.
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = [pscustomobject]@{ platformId='gb' } } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/list' -Body $b -State $s }
        $r.Status | Should -Be 200
        @($r.Body.names) | Should -Contain 'Tetris.gb'
        # Save favourites (also syncs).
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = [pscustomobject]@{ platformId='gb'; names=@('Tetris.gb') } } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/favorites' -Body $b -State $s }
        $r.Status | Should -Be 200
        ($r.Body.sync.LinkedCount + $r.Body.sync.CopiedCount) | Should -Be 1
        (Test-Path (Join-Path $common '!Favorites/Tetris.gb')) | Should -BeTrue
        # GET reflects the saved favourite.
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/favorites' -State $s }
        ($r.Body.Platforms | Where-Object PlatformId -eq 'gb').Names | Should -Contain 'Tetris.gb'
    }
    It 'GET/POST /api/cleanup reports leftovers and removes only empty/temp dirs' {
        New-Item -ItemType Directory -Path (Join-Path $script:root 'Assets/gb/common/EmptyBucket') -Force | Out-Null
        'rom' | Set-Content (Join-Path $script:root 'Assets/gb/common/keep.gb')
        $g = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/cleanup' -State $s }
        $g.Status | Should -Be 200
        @($g.Body.EmptyDirs) | Should -Contain (Join-Path $script:root 'Assets/gb/common/EmptyBucket')
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/cleanup' -State $s }
        $r.Body.RemovedCount | Should -BeGreaterOrEqual 1
        (Test-Path (Join-Path $script:root 'Assets/gb/common/EmptyBucket')) | Should -BeFalse
        (Test-Path (Join-Path $script:root 'Assets/gb/common/keep.gb')) | Should -BeTrue
    }
    It 'GET /api/profile/export + POST /api/profile/import round-trip config & favourites' {
        # Seed a source mapping + favourite, export, then import onto a fresh root.
        Save-PocketRomConfig -Root $script:state.Root -Sources @([pscustomobject]@{ SystemId='gb'; Path='/roms/gb'; Recurse=$true }) | Out-Null
        Save-PocketFavorite -Root $script:state.Root -PlatformId 'gb' -Names @('Tetris.gb') | Out-Null
        $exp = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/profile/export' -State $s }
        $exp.Status | Should -Be 200
        $exp.Body.romSources[0].systemId | Should -Be 'gb'

        $dest = Join-Path ([System.IO.Path]::GetTempPath()) ("pfimp_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory $dest -Force | Out-Null
        try {
            $st2 = $script:state.Clone(); $st2.Root = $dest
            $imp = InModuleScope PocketPrep -Parameters @{ s = $st2; b = [pscustomobject]@{ profile = $exp.Body } } { param($s,$b)
                Invoke-PocketApiRoute -Method POST -Path '/api/profile/import' -Body $b -State $s }
            $imp.Status | Should -Be 200
            $imp.Body.RomSourcesRestored | Should -Be 1
            (Get-PocketRomConfig -Root $dest).Exists | Should -BeTrue
            @(Get-PocketFavorite -Root $dest -PlatformId 'gb') | Should -Contain 'Tetris.gb'
        } finally { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'POST /api/card/onboard generates a config from existing card ROMs' {
        $common = Join-Path $script:root 'Assets/gb/common'; New-Item -ItemType Directory $common -Force | Out-Null
        'a' | Set-Content (Join-Path $common 'one.gb')
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/card/onboard' -Body ([pscustomobject]@{}) -State $s }
        $r.Status | Should -Be 200
        $r.Body.DetectedCount | Should -Be 1
        (Test-Path (Join-Path $script:state.Root 'pocketprep/rom-sources.json')) | Should -BeTrue
    }
    It 'GET/POST /api/rom/config round-trips and POST /api/rom/rescan copies' {
        $src = Join-Path $script:root '_rcfg'; New-Item -ItemType Directory $src -Force | Out-Null
        'a' | Set-Content (Join-Path $src 'one.gb'); 'b' | Set-Content (Join-Path $src 'two.gb')

        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/rom/config' -State $s }
        $r.Body.Exists | Should -BeFalse

        $body = [pscustomobject]@{ sources = @([pscustomobject]@{ systemId='gb'; path=$src; recurse=$false }) }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/config' -Body $b -State $s }
        $r.Status | Should -Be 200
        $r.Body.SourceCount | Should -Be 1

        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/rescan' -Body ([pscustomobject]@{}) -State $s }
        $r.Status | Should -Be 200
        $r.Body.TotalCopied | Should -Be 2
        (Test-Path (Join-Path $script:state.Root 'Assets/gb/common/one.gb')) | Should -BeTrue
    }
    It 'POST /api/target sets a test-mode root' {
        $newRoot = Join-Path $script:root 'chosen'
        $body = [pscustomobject]@{ testMode = $true; rootPath = $newRoot }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/target' -Body $b -State $s }
        $r.Status | Should -Be 200
        $r.Body.ready | Should -BeTrue
        $script:state.Root | Should -Be (Resolve-Path $newRoot).Path
    }
    It 'POST /api/target rejects an unsafe (system) drive' {
        $body = [pscustomobject]@{ drive = [pscustomobject]@{ DriveLetter='/'; RootPath='/'; IsRemovable=$false; SizeBytes=1TB } }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/target' -Body $b -State $s }
        $r.Status | Should -Be 400
        $r.Body.verdict | Should -Not -BeNullOrEmpty
    }
    It 'POST /api/rom/plan includes PlatformProvided' {
        $src = Join-Path $script:root '_src2'; New-Item -ItemType Directory $src -Force | Out-Null
        'x' | Set-Content (Join-Path $src 'g.gb')
        $body = [pscustomobject]@{ systemId='gb'; sourceFolder=$src }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/plan' -Body $b -State $s }
        $r.Body.PSObject.Properties.Name | Should -Contain 'PlatformProvided'
        $r.Body.PlatformProvided | Should -BeFalse   # no cores installed in this temp root
    }
    It 'GET /api/cores/integrity flags a core missing required files' {
        $cd = Join-Path $script:root 'Cores/broken.Core'; New-Item -ItemType Directory $cd -Force | Out-Null
        @{ core = @{ metadata = @{ shortname='B'; author='x'; version='1'; platform_ids=@('gb') } } } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cd 'core.json')
        # only core.json present -> missing data/video/input
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/cores/integrity' -State $s }
        $r.Status | Should -Be 200
        ($r.Body.cores | Where-Object Identifier -eq 'broken.Core').Ok | Should -BeFalse
    }
    It 'POST /api/cores/repair rejects a missing coreId' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/cores/repair' -Body ([pscustomobject]@{}) -State $s }
        $r.Status | Should -Be 400
    }
    It 'GET /api/cores/updates returns an updates array' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/cores/updates' -State $s }
        $r.Status | Should -Be 200
        $r.Body.ContainsKey('updates') | Should -BeTrue
    }
    It 'unknown route returns 404' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/nope' -State $s }
        $r.Status | Should -Be 404
    }
    It 'route errors are returned as 400, not thrown' {
        $body = [pscustomobject]@{ systemId='gb'; sourceFolder='/does/not/exist' }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s,$b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/plan' -Body $b -State $s }
        $r.Status | Should -Be 400
        $r.Body.error | Should -Not -BeNullOrEmpty
    }
}

Describe 'Test-PocketApiRequest (auth)' {
    It 'allows a request with the right token and loopback host' {
        $r = InModuleScope PocketPrep {
            Test-PocketApiRequest -Headers @{ 'X-PocketPrep-Token'='abc'; 'Host'='127.0.0.1:9999' } -ExpectedToken 'abc' -Port 9999 }
        $r.Allowed | Should -BeTrue
    }
    It 'rejects a missing/incorrect token (401)' {
        $r = InModuleScope PocketPrep {
            Test-PocketApiRequest -Headers @{ 'Host'='127.0.0.1:9999' } -ExpectedToken 'abc' -Port 9999 }
        $r.Allowed | Should -BeFalse
        $r.Status | Should -Be 401
    }
    It 'rejects a foreign Host header (403)' {
        $r = InModuleScope PocketPrep {
            Test-PocketApiRequest -Headers @{ 'X-PocketPrep-Token'='abc'; 'Host'='evil.example.com' } -ExpectedToken 'abc' -Port 9999 }
        $r.Status | Should -Be 403
    }
    It 'rejects a cross-origin request (403)' {
        $r = InModuleScope PocketPrep {
            Test-PocketApiRequest -Headers @{ 'X-PocketPrep-Token'='abc'; 'Host'='127.0.0.1:9999'; 'Origin'='http://evil.example.com' } -ExpectedToken 'abc' -Port 9999 }
        $r.Status | Should -Be 403
    }
}
