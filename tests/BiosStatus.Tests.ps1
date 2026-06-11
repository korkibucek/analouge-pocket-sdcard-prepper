BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:systemsManifest = Join-Path $repo 'manifests/systems.json'
}

Describe 'Get-PocketBiosStatus' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("bios_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'reports Neo Geo BIOS as missing on a fresh card' {
        $ng = Get-PocketBiosStatus -Root $script:root -SystemsManifest $script:systemsManifest -SystemId 'neogeo'
        @($ng).Count | Should -Be 1
        $ng.Satisfied | Should -BeFalse
        $ng.Missing | Should -Contain 'uni-bios_4_0.rom'
        $ng.Missing | Should -Contain '000-lo.lo'
        $ng.Missing | Should -Contain 'sfix.sfix'
    }

    It 'reports satisfied once the BIOS file is placed (case-insensitive)' {
        $common = Join-Path $script:root 'Assets/ng/common'
        New-Item -ItemType Directory -Path $common -Force | Out-Null
        'bios' | Set-Content (Join-Path $common 'UNI-BIOS_4_0.ROM')   # different case
        'lo'   | Set-Content (Join-Path $common '000-LO.LO')
        'sfix' | Set-Content (Join-Path $common 'SFIX.SFIX')
        $ng = Get-PocketBiosStatus -Root $script:root -SystemsManifest $script:systemsManifest -SystemId 'neogeo'
        $ng.Satisfied | Should -BeTrue
        $ng.Present | Should -Contain 'uni-bios_4_0.rom'
    }

    It 'only lists systems that require a BIOS' {
        $all = Get-PocketBiosStatus -Root $script:root -SystemsManifest $script:systemsManifest
        @($all | ForEach-Object { $_.SystemId }) | Should -Not -Contain 'gb'   # GB needs no BIOS
        @($all | ForEach-Object { $_.SystemId }) | Should -Contain 'neogeo'
    }
}
