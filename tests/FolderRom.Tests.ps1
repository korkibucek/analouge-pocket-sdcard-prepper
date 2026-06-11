BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:manifest = Join-Path $repo 'manifests/systems.json'
}

# Folder-format systems (#200): each game is a whole directory (Neo Geo DarkSoft sets).
Describe 'New-/Invoke-PocketRomCopyPlan (folder-format systems)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fr_" + [System.IO.Path]::GetRandomFileName())
        $script:src  = Join-Path $script:root '_src'
        foreach ($game in 'mslug4', 'kof98') {
            $d = Join-Path $script:src $game
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            foreach ($f in 'prom', 'srom', 'crom0', 'm1rom', 'vroma0') { "data-$game-$f" | Set-Content (Join-Path $d $f) }
        }
        # A loose file next to the game folders (e.g. a stray readme) must be ignored.
        'stray' | Set-Content (Join-Path $script:src 'readme.txt')
        $script:sys = Get-PocketSystem -Path $script:manifest -Id neogeo
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'plans one entry per file, grouped under game folders, ignoring loose files' {
        $p = New-PocketRomCopyPlan -System $script:sys -SourceFolder $script:src -Root $script:root
        $p.RomFormat | Should -Be 'folder'
        $p.GameCount | Should -Be 2
        @($p.Games) | Should -Be @('kof98', 'mslug4')
        $p.FileCount | Should -Be 10
        @($p.Items | Where-Object { $_.RelativePath -like 'readme*' }).Count | Should -Be 0
        # Destinations keep the game folder under Assets/ng/common.
        $p.Items[0].Destination | Should -Match 'Assets'
        @($p.Items | Where-Object { $_.RelativePath -eq 'mslug4/prom' }).Count | Should -Be 1
    }

    It 'copies whole game folders and a second run skips existing files' {
        $p = New-PocketRomCopyPlan -System $script:sys -SourceFolder $script:src -Root $script:root
        $r = Invoke-PocketRomCopyPlan -Plan $p -SkipSpaceCheck
        $r.CopiedCount | Should -Be 10
        $common = Join-Path $script:root 'Assets/ng/common'
        Test-Path (Join-Path $common 'mslug4/crom0') | Should -BeTrue
        Test-Path (Join-Path $common 'kof98/vroma0') | Should -BeTrue
        (Get-Content (Join-Path $common 'mslug4/prom')) | Should -Be 'data-mslug4-prom'
        $r2 = Invoke-PocketRomCopyPlan -Plan $p -SkipSpaceCheck
        $r2.CopiedCount | Should -Be 0
        $r2.SkippedCount | Should -Be 10
    }

    It 'imports a single game folder when pointed directly at it' {
        $p = New-PocketRomCopyPlan -System $script:sys -SourceFolder (Join-Path $script:src 'mslug4') -Root $script:root
        $p.GameCount | Should -Be 1
        @($p.Games) | Should -Be @('mslug4')
        $r = Invoke-PocketRomCopyPlan -Plan $p -SkipSpaceCheck
        Test-Path (Join-Path $script:root 'Assets/ng/common/mslug4/srom') | Should -BeTrue
    }

    It 'does not content-dedupe identical support files across different games' {
        # Two games with byte-identical files must both land in full.
        Set-Content (Join-Path $script:src 'mslug4/m1rom') -Value 'same-bytes'
        Set-Content (Join-Path $script:src 'kof98/m1rom') -Value 'same-bytes'
        $p = New-PocketRomCopyPlan -System $script:sys -SourceFolder $script:src -Root $script:root
        $p.DuplicateCount | Should -Be 0
        $p.CopyableCount | Should -Be 10
    }
}

Describe 'Get-PocketInstanceGame' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("ig_" + [System.IO.Path]::GetRandomFileName())
        $core = Join-Path $script:root 'Assets/ng/Fake.NeoGeo'
        New-Item -ItemType Directory -Path $core -Force | Out-Null
        '{"instance":{"magic":"APF_VER_1","data_path":"mslug4","data_slots":[]}}' | Set-Content (Join-Path $core 'Metal Slug 4.json')
        '{"instance":{"magic":"APF_VER_1","data_path":"kof98","data_slots":[]}}' | Set-Content (Join-Path $core "King of Fighters '98.json")
        '{"not":"an instance"}' | Set-Content (Join-Path $core 'variants.json')
        $installed = Join-Path $script:root 'Assets/ng/common/mslug4'
        New-Item -ItemType Directory -Path $installed -Force | Out-Null
        'x' | Set-Content (Join-Path $installed 'prom')
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'maps instance jsons to titles/data paths and reports installed state' {
        $games = @(Get-PocketInstanceGame -Root $script:root -PlatformId ng)
        $games.Count | Should -Be 2     # variants.json (no data_path) ignored
        $slug = $games | Where-Object DataPath -eq 'mslug4'
        $slug.Title | Should -Be 'Metal Slug 4'
        $slug.Installed | Should -BeTrue
        ($games | Where-Object DataPath -eq 'kof98').Installed | Should -BeFalse
    }

    It 'returns empty for a platform with no core folders' {
        @(Get-PocketInstanceGame -Root $script:root -PlatformId gb).Count | Should -Be 0
    }
}

Describe 'Folder-format integration (summary / rom-list / organizer guard / health)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fi_" + [System.IO.Path]::GetRandomFileName())
        $repo = Split-Path -Parent $PSScriptRoot
        $script:state = @{
            Root = $script:root; IsTestMode = $true; DryRun = $false
            SystemsManifest = (Join-Path $repo 'manifests/systems.json')
            CoresManifest   = (Join-Path $repo 'manifests/cores.json')
        }
        $common = Join-Path $script:root 'Assets/ng/common'
        foreach ($g in 'mslug4', 'unknowngame') {
            New-Item -ItemType Directory -Path (Join-Path $common $g) -Force | Out-Null
            'x' | Set-Content (Join-Path (Join-Path $common $g) 'prom')
        }
        'bios' | Set-Content (Join-Path $common 'uni-bios_4_0.rom')
        $core = Join-Path $script:root 'Assets/ng/Fake.NeoGeo'
        New-Item -ItemType Directory -Path $core -Force | Out-Null
        '{"instance":{"data_path":"mslug4"}}' | Set-Content (Join-Path $core 'Metal Slug 4.json')
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'card summary counts game folders (not loose support files) for ng' {
        $sum = Get-PocketCardSummary -Root $script:root -SystemsManifest $script:state.SystemsManifest
        $ng = @($sum.Roms.Systems) | Where-Object PlatformId -eq 'ng'
        $ng.FileCount | Should -Be 2      # two game folders; the bios file is not a ROM
        $ng.RomFormat | Should -Be 'folder'
    }

    It 'POST /api/rom/list returns game folders with instance-json titles for ng' {
        $body = [pscustomobject]@{ platformId = 'ng' }
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s, $b)
            Invoke-PocketApiRoute -Method POST -Path '/api/rom/list' -Body $b -State $s }
        $r.Body.romFormat | Should -Be 'folder'
        @($r.Body.names) | Should -Be @('mslug4', 'unknowngame')
        $r.Body.titles['mslug4'] | Should -Be 'Metal Slug 4'
    }

    It 'refuses to organize a folder-format platform (it would break every game)' {
        foreach ($path in '/api/rom/organize/plan', '/api/rom/organize') {
            $body = [pscustomobject]@{ platformId = 'ng' }
            $r = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body; p = $path } { param($s, $b, $p)
                Invoke-PocketApiRoute -Method POST -Path $p -Body $b -State $s }
            $r.Status | Should -Be 400
            $r.Body.error | Should -Match 'folder'
        }
    }

    It 'health check warns about game folders no instance json points at' {
        $rep = Get-PocketHealthReport -Root $script:root -SystemsManifest $script:state.SystemsManifest -CoresManifest $script:state.CoresManifest
        $check = @($rep.Checks) | Where-Object Name -eq 'Neo Geo game folders'
        $check.Status | Should -Be 'warn'
        $check.Detail | Should -Match 'unknowngame'
    }

    It 'health check passes when every game folder matches an instance json' {
        Remove-Item (Join-Path $script:root 'Assets/ng/common/unknowngame') -Recurse -Force
        $rep = Get-PocketHealthReport -Root $script:root -SystemsManifest $script:state.SystemsManifest -CoresManifest $script:state.CoresManifest
        $check = @($rep.Checks) | Where-Object Name -eq 'Neo Geo game folders'
        $check.Status | Should -Be 'ok'
    }
}
