BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:srcs = Join-Path $repo 'manifests/image-sources.json'

    function New-GbCard {
        param($Root, [string[]]$Names)
        $common = Join-Path $Root 'Assets/gb/common'
        New-Item -ItemType Directory -Path $common -Force | Out-Null
        foreach ($n in $Names) { 'rom' | Set-Content (Join-Path $common $n) }
    }
    # Fake index covering exact, case-different, and tag-different titles.
    $script:fakeTree = [pscustomobject]@{ tree = @(
        [pscustomobject]@{ path = 'Named_Boxarts/Tetris (World) (Rev 1).png' }
        [pscustomobject]@{ path = 'Named_Boxarts/Sonic The Hedgehog (World).png' }
        [pscustomobject]@{ path = 'Named_Boxarts/Mega Man V (USA).png' }
        [pscustomobject]@{ path = 'README.md' }
    ) }
}

Describe 'Sync-PocketGameImage (mocked network)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("gi_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'fetches art only for matched games on the card (exact, case-insensitive, tag-stripped)' {
        New-GbCard $script:root @(
            'Tetris (World) (Rev 1).gb',     # exact
            'sonic the hedgehog (World).gb', # case-insensitive
            'Mega Man V (USA) (Rev A).gb',   # tag-stripped fallback
            'Totally Unknown Homebrew.gb'    # no match
        )
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; srcs = $script:srcs; tree = $script:fakeTree } {
            param($root, $srcs, $tree)
            Mock Invoke-PocketRest { $tree }
            Mock Invoke-PocketDownload { 'png' | Set-Content -LiteralPath $OutFile; $OutFile }
            Sync-PocketGameImage -Root $root -PlatformId 'gb' -ImageSources $srcs
        }
        $r.Supported | Should -BeTrue
        $r.Fetched | Should -Be 3
        $r.MissingCount | Should -Be 1
        $r.Missing | Should -Contain 'Totally Unknown Homebrew'
        # Cached by ROM basename, so the UI can map directly.
        (Test-Path (Join-Path $script:root 'pocketprep/images/gb/Tetris (World) (Rev 1).png')) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'pocketprep/images/gb/sonic the hedgehog (World).png')) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'pocketprep/images/gb/Mega Man V (USA) (Rev A).png')) | Should -BeTrue
        # The repo index was fetched once and cached.
        (Test-Path (Join-Path $script:root 'pocketprep/images/gb/.index.json')) | Should -BeTrue
    }

    It 'is incremental: cached images are skipped and the index is reused (no API call)' {
        New-GbCard $script:root @('Tetris (World) (Rev 1).gb')
        InModuleScope PocketPrep -Parameters @{ root = $script:root; srcs = $script:srcs; tree = $script:fakeTree } {
            param($root, $srcs, $tree)
            Mock Invoke-PocketRest { $tree }
            Mock Invoke-PocketDownload { 'png' | Set-Content -LiteralPath $OutFile; $OutFile }
            Sync-PocketGameImage -Root $root -PlatformId 'gb' -ImageSources $srcs | Out-Null
        }
        $r2 = InModuleScope PocketPrep -Parameters @{ root = $script:root; srcs = $script:srcs } {
            param($root, $srcs)
            Mock Invoke-PocketRest { throw 'index must come from cache' }
            Mock Invoke-PocketDownload { throw 'nothing new to download' }
            Sync-PocketGameImage -Root $root -PlatformId 'gb' -ImageSources $srcs
        }
        $r2.AlreadyCached | Should -Be 1
        $r2.Fetched | Should -Be 0
    }

    It 'respects the per-run cap and reports the remainder' {
        New-GbCard $script:root @('Tetris (World) (Rev 1).gb', 'Sonic The Hedgehog (World).gb', 'Mega Man V (USA).gb')
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; srcs = $script:srcs; tree = $script:fakeTree } {
            param($root, $srcs, $tree)
            Mock Invoke-PocketRest { $tree }
            Mock Invoke-PocketDownload { 'png' | Set-Content -LiteralPath $OutFile; $OutFile }
            Sync-PocketGameImage -Root $root -PlatformId 'gb' -ImageSources $srcs -MaxNew 2
        }
        $r.Fetched | Should -Be 2
        $r.Remaining | Should -Be 1
    }

    It 'reports unsupported platforms gracefully and DryRun downloads nothing' {
        (Sync-PocketGameImage -Root $script:root -PlatformId 'no-such-platform' -ImageSources $script:srcs).Supported | Should -BeFalse
        New-GbCard $script:root @('Tetris (World) (Rev 1).gb')
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; srcs = $script:srcs; tree = $script:fakeTree } {
            param($root, $srcs, $tree)
            Mock Invoke-PocketRest { $tree }
            Mock Invoke-PocketDownload { throw 'must not download in dry-run' }
            Sync-PocketGameImage -Root $root -PlatformId 'gb' -ImageSources $srcs -DryRun
        }
        $r.DryRun | Should -BeTrue
        (Test-Path (Join-Path $script:root 'pocketprep/images/gb/Tetris (World) (Rev 1).png')) | Should -BeFalse
    }
}
