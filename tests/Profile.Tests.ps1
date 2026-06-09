BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:cm = Join-Path $repo 'manifests/cores.json'
    $script:sm = Join-Path $repo 'manifests/systems.json'
}

Describe 'Export-PocketProfile' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pf_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'captures installed cores (with catalog id), ROM sources and favourites' {
        # An installed core whose Identifier matches a catalog entry.
        $first = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $script:cm) | Select-Object -First 1
        $cd = Join-Path $script:root "Cores/$($first.Identifier)"; New-Item -ItemType Directory $cd -Force | Out-Null
        @{ core = @{ metadata = @{ shortname='X'; author='a'; version='1.2'; platform_ids=@('gb') } } } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cd 'core.json')
        Save-PocketRomConfig -Root $script:root -Sources @([pscustomobject]@{ SystemId='gb'; Path='/roms/gb'; Recurse=$true }) | Out-Null
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('Tetris.gb') | Out-Null

        $p = Export-PocketProfile -Root $script:root -CoresManifest $script:cm
        ($p.cores | Where-Object identifier -eq $first.Identifier).id | Should -Be $first.Id
        $p.romSources[0].systemId | Should -Be 'gb'
        $p.romSources[0].recurse | Should -BeTrue
        ($p.favorites | Where-Object platformId -eq 'gb').names | Should -Contain 'Tetris.gb'
    }
}

Describe 'Import-PocketProfile' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pfi_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'restores ROM config and favourites; plans core installs (dry-run, no download)' {
        $profile = [pscustomobject]@{
            version = 1
            cores = @([pscustomobject]@{ identifier = 'agg23.NES'; id = (Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $script:cm) | Select-Object -First 1).Id; version = '1' })
            romSources = @([pscustomobject]@{ systemId = 'gb'; path = '/roms/gb'; recurse = $false })
            favorites = @([pscustomobject]@{ platformId = 'gb'; names = @('A.gb') })
        }
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; sm = $script:sm; prof = $profile } {
            param($root, $cm, $sm, $prof)
            Mock Install-PocketCore { [pscustomobject]@{ PlacedCount = 0; DryRun = $true } }
            Import-PocketProfile -Root $root -ProfileData $prof -CoresManifest $cm -SystemsManifest $sm -DryRun
        }
        $r.RomSourcesRestored | Should -Be 1
        $r.FavoritesRestored | Should -Be 1
        $r.CoresRequested | Should -Be 1
        # Even in dry-run, the config write itself isn't performed (Save honours -DryRun).
        (Get-PocketRomConfig -Root $script:root).Exists | Should -BeFalse
    }

    It 'actually restores config + favourites when not dry-run' {
        $profile = [pscustomobject]@{
            version = 1; cores = @()
            romSources = @([pscustomobject]@{ systemId = 'gb'; path = '/roms/gb'; recurse = $false })
            favorites = @([pscustomobject]@{ platformId = 'gb'; names = @('A.gb') })
        }
        Import-PocketProfile -Root $script:root -ProfileData $profile | Out-Null
        (Get-PocketRomConfig -Root $script:root).Exists | Should -BeTrue
        @(Get-PocketFavorite -Root $script:root -PlatformId 'gb') | Should -Contain 'A.gb'
    }
}
