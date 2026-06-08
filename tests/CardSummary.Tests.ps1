BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:systemsManifest  = Join-Path $repo 'manifests/systems.json'
    $script:firmwareManifest = Join-Path $repo 'manifests/firmware.json'
}

Describe 'Get-PocketCardSummary' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("sum_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'reports an empty card with nothing installed' {
        $s = Get-PocketCardSummary -Root $script:root
        $s.Firmware.Present | Should -BeFalse
        $s.Cores.Count | Should -Be 0
        $s.Roms.TotalFiles | Should -Be 0
        $s.Config.Exists | Should -BeFalse
    }

    It 'detects firmware and resolves its version from the filename' {
        'fw' | Set-Content (Join-Path $script:root 'pocket_firmware_2_5.bin')
        $s = Get-PocketCardSummary -Root $script:root -FirmwareManifest $script:firmwareManifest
        $s.Firmware.Present | Should -BeTrue
        $s.Firmware.FileName | Should -Be 'pocket_firmware_2_5.bin'
        $s.Firmware.Version | Should -Be '2.5'
    }

    It 'counts ROMs per platform and labels them from the systems manifest' {
        $common = Join-Path $script:root 'Assets/gb/common'
        New-Item -ItemType Directory -Path $common -Force | Out-Null
        'a' | Set-Content (Join-Path $common 'one.gb')
        'b' | Set-Content (Join-Path $common 'two.gb')
        $s = Get-PocketCardSummary -Root $script:root -SystemsManifest $script:systemsManifest
        $s.Roms.TotalFiles | Should -Be 2
        $gb = $s.Roms.Systems | Where-Object PlatformId -eq 'gb'
        $gb.FileCount | Should -Be 2
        $gb.SystemId | Should -Be 'gb'
        $gb.DisplayName | Should -Not -BeNullOrEmpty
    }

    It 'reports installed cores' {
        $coreDir = Join-Path $script:root 'Cores/Test.Core'
        New-Item -ItemType Directory -Path $coreDir -Force | Out-Null
        @{ core = @{ metadata = @{ shortname = 'Test'; author = 'me'; version = '1.0'; platform_ids = @('gb') } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $coreDir 'core.json')
        $s = Get-PocketCardSummary -Root $script:root
        $s.Cores.Count | Should -Be 1
        $s.Cores.Items[0].Identifier | Should -Be 'Test.Core'
        $s.Cores.Items[0].Version | Should -Be '1.0'
    }

    It 'surfaces the saved ROM config when present' {
        Save-PocketRomConfig -Root $script:root -Sources @([pscustomobject]@{ SystemId='gb'; Path='/x' }) | Out-Null
        $s = Get-PocketCardSummary -Root $script:root
        $s.Config.Exists | Should -BeTrue
        $s.Config.SourceCount | Should -Be 1
    }
}
