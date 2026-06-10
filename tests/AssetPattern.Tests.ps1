BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:cm = Join-Path $repo 'manifests/cores.json'
}

Describe 'assetPattern in the cores manifest (multi-zip releases, #176)' {
    BeforeAll {
        $script:cores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $script:cm)
    }

    It 'gives classic GB and GBC (same repo) DIFFERENT asset patterns' {
        $gb  = $script:cores | Where-Object Identifier -eq 'Spiritualized.GB'
        $gbc = $script:cores | Where-Object Identifier -eq 'Spiritualized.GBC'
        $gb.AssetPattern  | Should -Be '_GB_'
        $gbc.AssetPattern | Should -Be '_GBC_'
        $gb.Repo | Should -Be $gbc.Repo   # same repo, two zips
        # The patterns each match exactly one of the real release assets.
        'Spiritualized_GB_1.3.0_2022_08_25.zip'  -match $gb.AssetPattern  | Should -BeTrue
        'Spiritualized_GBC_1.3.0_2022_08_25.zip' -match $gb.AssetPattern  | Should -BeFalse
        'Spiritualized_GBC_1.3.0_2022_08_25.zip' -match $gbc.AssetPattern | Should -BeTrue
    }

    It 'pins agg23 Game & Watch / Tamagotchi to the Pocket build (not MiSTer)' {
        foreach ($id in 'agg23-gameandwatch', 'agg23-tamagotchi') {
            ($script:cores | Where-Object Id -eq $id).AssetPattern | Should -Be 'Pocket'
        }
        'agg23.GameAndWatch_0.2.0_2023-06-30-Pocket.zip' -match 'Pocket' | Should -BeTrue
        'agg23.GameAndWatch_0.2.0_2023-06-30-MiSTer.zip' -match 'Pocket' | Should -BeFalse
    }

    It 'separates budude2 classic GB and GBC zips from the shared repo' {
        $gb  = $script:cores | Where-Object Id -eq 'budude2-gb'
        $gbc = $script:cores | Where-Object Id -eq 'budude2-gbc'
        $gb | Should -Not -BeNullOrEmpty
        'openfpga-gb-1.4.0.zip'  -match $gb.AssetPattern  | Should -BeTrue
        'openfpga-gbc-1.4.0.zip' -match $gb.AssetPattern  | Should -BeFalse
        'openfpga-gbc-1.4.0.zip' -match $gbc.AssetPattern | Should -BeTrue
    }

    It 'pins opengateware arcade cores to the pocket zip' {
        ($script:cores | Where-Object Id -eq 'boogermann-gberet').AssetPattern | Should -Be 'pocket'
        'arcade-galaga-pocket-v0.1.0.zip' -match 'pocket' | Should -BeTrue          # hyphen naming
        'boogermann.gberet_rom-recipes-0.1.1.zip' -match 'pocket' | Should -BeFalse # never the recipes
    }

    It 'Install-PocketCoreSet installs BOTH cores of a shared repo (dedupe by repo+pattern)' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("ap_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        try {
            $r = InModuleScope PocketPrep -Parameters @{ root = $root; cm = $script:cm } {
                param($root, $cm)
                Mock Install-PocketCore { [pscustomobject]@{ PlacedCount = 1; Version = '1.0' } }
                $res = Install-PocketCoreSet -Root $root -CoresManifest $cm -Id @('spiritualized-gb', 'spiritualized-gbc')
                Assert-MockCalled Install-PocketCore -Times 1 -ParameterFilter { $Core.AssetPattern -eq '_GB_' }
                Assert-MockCalled Install-PocketCore -Times 1 -ParameterFilter { $Core.AssetPattern -eq '_GBC_' }
                $res
            }
            @($r.Results).Count | Should -Be 2   # previously the repo-dedupe collapsed this to 1
        } finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'Install-PocketCore forwards the pattern to the release resolver' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("apf_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        try {
            InModuleScope PocketPrep -Parameters @{ root = $root; cm = $script:cm } {
                param($root, $cm)
                Mock Get-PocketLatestRelease { [pscustomobject]@{ Version = 'v1'; ZipUrl = 'https://github.com/x.zip'; ZipName = 'x.zip' } }
                $core = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $cm) -Id 'spiritualized-gb'
                Install-PocketCore -Root $root -Core $core -Download -DryRun | Out-Null
                Assert-MockCalled Get-PocketLatestRelease -Times 1 -ParameterFilter { $AssetPattern -eq '_GB_' }
            }
        } finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
