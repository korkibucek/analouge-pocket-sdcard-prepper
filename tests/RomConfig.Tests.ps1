BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:repo = $repo
    $script:systemsManifest = Join-Path $repo 'manifests/systems.json'
}

Describe 'Get/Save-PocketRomConfig' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("cfg_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'returns an empty, valid config when none exists' {
        $c = Get-PocketRomConfig -Root $script:root
        $c.Exists | Should -BeFalse
        @($c.Sources).Count | Should -Be 0
        $c.Version | Should -Be 1
    }

    It 'round-trips saved sources' {
        $src = @(
            [pscustomobject]@{ SystemId = 'gb';  Path = '/roms/gb';  Recurse = $false }
            [pscustomobject]@{ SystemId = 'nes'; Path = '/roms/nes'; Recurse = $true }
        )
        $res = Save-PocketRomConfig -Root $script:root -Sources $src
        $res.Written | Should -BeTrue
        $res.SourceCount | Should -Be 2
        (Test-Path (Join-Path $script:root 'pocketprep/rom-sources.json')) | Should -BeTrue

        $c = Get-PocketRomConfig -Root $script:root
        $c.Exists | Should -BeTrue
        @($c.Sources).Count | Should -Be 2
        ($c.Sources | Where-Object SystemId -eq 'nes').Recurse | Should -BeTrue
    }

    It 'de-duplicates sources by system+path' {
        $src = @(
            [pscustomobject]@{ SystemId = 'gb'; Path = '/roms/gb'; Recurse = $false }
            [pscustomobject]@{ SystemId = 'gb'; Path = '/roms/gb'; Recurse = $false }
        )
        (Save-PocketRomConfig -Root $script:root -Sources $src).SourceCount | Should -Be 1
    }

    It 'accepts hashtable / lower-case JSON-style sources' {
        $src = @(@{ systemId = 'gb'; path = '/roms/gb'; recurse = $true })
        (Save-PocketRomConfig -Root $script:root -Sources $src).SourceCount | Should -Be 1
        (Get-PocketRomConfig -Root $script:root).Sources[0].Recurse | Should -BeTrue
    }

    It 'throws on a source missing systemId or path' {
        { Save-PocketRomConfig -Root $script:root -Sources @([pscustomobject]@{ SystemId = 'gb' }) } | Should -Throw
    }

    It '-DryRun does not write the file' {
        $res = Save-PocketRomConfig -Root $script:root -Sources @([pscustomobject]@{ SystemId='gb'; Path='/x' }) -DryRun
        $res.Written | Should -BeFalse
        (Test-Path (Join-Path $script:root 'pocketprep/rom-sources.json')) | Should -BeFalse
    }

    It 'tolerates a corrupt config file (returns empty, no throw)' {
        New-Item -ItemType Directory -Path (Join-Path $script:root 'pocketprep') -Force | Out-Null
        'not json{' | Set-Content (Join-Path $script:root 'pocketprep/rom-sources.json')
        $c = Get-PocketRomConfig -Root $script:root -WarningAction SilentlyContinue
        $c.Exists | Should -BeFalse
    }
}

Describe 'Invoke-PocketRomRescan' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("rsc_" + [System.IO.Path]::GetRandomFileName())
        $script:gbSrc = Join-Path ([System.IO.Path]::GetTempPath()) ("rscsrc_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root, $script:gbSrc -Force | Out-Null
        'a' | Set-Content (Join-Path $script:gbSrc 'one.gb')
        'b' | Set-Content (Join-Path $script:gbSrc 'two.gb')
        Save-PocketRomConfig -Root $script:root -Sources @([pscustomobject]@{ SystemId='gb'; Path=$script:gbSrc; Recurse=$false }) | Out-Null
    }
    AfterEach { Remove-Item $script:root, $script:gbSrc -Recurse -Force -ErrorAction SilentlyContinue }

    It 'copies ROMs from every saved source' {
        $r = Invoke-PocketRomRescan -Root $script:root -SystemsManifest $script:systemsManifest
        $r.SourceCount | Should -Be 1
        $r.TotalCopied | Should -Be 2
        (Test-Path (Join-Path $script:root 'Assets/gb/common/one.gb')) | Should -BeTrue
    }

    It 'picks up newly-added ROMs on a second rescan' {
        Invoke-PocketRomRescan -Root $script:root -SystemsManifest $script:systemsManifest | Out-Null
        'c' | Set-Content (Join-Path $script:gbSrc 'three.gb')
        $r2 = Invoke-PocketRomRescan -Root $script:root -SystemsManifest $script:systemsManifest
        $r2.TotalCopied | Should -Be 1   # only the new file (existing ones skipped)
        (Test-Path (Join-Path $script:root 'Assets/gb/common/three.gb')) | Should -BeTrue
    }

    It 'reports a missing source folder without failing the rescan' {
        Remove-Item $script:gbSrc -Recurse -Force
        $r = Invoke-PocketRomRescan -Root $script:root -SystemsManifest $script:systemsManifest
        $r.Results[0].Missing | Should -BeTrue
        $r.TotalCopied | Should -Be 0
    }
}
