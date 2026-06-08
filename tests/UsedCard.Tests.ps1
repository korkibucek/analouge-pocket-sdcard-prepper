BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:systemsManifest = Join-Path $repo 'manifests/systems.json'
}

Describe 'Import-PocketUsedCard' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("used_" + [System.IO.Path]::GetRandomFileName())
        # Fabricate a used card: GB + NES ROMs already present, plus an unknown platform.
        foreach ($p in 'gb', 'nes', 'mystery') {
            $common = Join-Path $script:root "Assets/$p/common"
            New-Item -ItemType Directory -Path $common -Force | Out-Null
            'rom' | Set-Content (Join-Path $common "game.$p")
        }
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'generates a valid config from the systems detected on the card' {
        $r = Import-PocketUsedCard -Root $script:root -SystemsManifest $script:systemsManifest
        $r.DetectedCount | Should -Be 2          # gb + nes map to known systems
        $r.Config.Written | Should -BeTrue
        (Test-Path (Join-Path $script:root 'pocketprep/rom-sources.json')) | Should -BeTrue

        $cfg = Get-PocketRomConfig -Root $script:root
        @($cfg.Sources | ForEach-Object { $_.SystemId }) | Should -Contain 'gb'
        @($cfg.Sources | ForEach-Object { $_.SystemId }) | Should -Contain 'nes'
        # The generated source points at the card's own common folder.
        ($cfg.Sources | Where-Object SystemId -eq 'gb').Path | Should -Match 'Assets.*gb.*common'
    }

    It 'reports platforms with no matching system as unmapped (does not invent a mapping)' {
        $r = Import-PocketUsedCard -Root $script:root -SystemsManifest $script:systemsManifest
        $r.UnmappedCount | Should -Be 1
        $r.Unmapped[0].PlatformId | Should -Be 'mystery'
    }

    It 'a generated config rescans as a safe no-op (everything already present)' {
        Import-PocketUsedCard -Root $script:root -SystemsManifest $script:systemsManifest | Out-Null
        $rescan = Invoke-PocketRomRescan -Root $script:root -SystemsManifest $script:systemsManifest
        $rescan.TotalCopied | Should -Be 0       # files already on the card are skipped
    }

    It '-DryRun does not write the config' {
        $r = Import-PocketUsedCard -Root $script:root -SystemsManifest $script:systemsManifest -DryRun
        $r.DryRun | Should -BeTrue
        (Test-Path (Join-Path $script:root 'pocketprep/rom-sources.json')) | Should -BeFalse
    }

    It 'preserves existing saved sources when onboarding' {
        Save-PocketRomConfig -Root $script:root -Sources @([pscustomobject]@{ SystemId='snes'; Path='/my/snes' }) | Out-Null
        Import-PocketUsedCard -Root $script:root -SystemsManifest $script:systemsManifest | Out-Null
        $cfg = Get-PocketRomConfig -Root $script:root
        @($cfg.Sources | ForEach-Object { $_.SystemId }) | Should -Contain 'snes'   # kept
        ($cfg.Sources | Where-Object SystemId -eq 'snes').Path | Should -Be '/my/snes'
    }
}
