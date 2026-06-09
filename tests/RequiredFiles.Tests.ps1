BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    function New-CoreWithData {
        param($Root, $Identifier, $PlatformId, [object[]]$Slots)
        $coreDir = Join-Path $Root "Cores/$Identifier"
        New-Item -ItemType Directory -Path $coreDir -Force | Out-Null
        @{ core = @{ metadata = @{ shortname = $Identifier; author = 'x'; version = '1'; platform_ids = @($PlatformId) } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $coreDir 'core.json')
        @{ data = @{ magic = 'APF_VER_1'; data_slots = $Slots } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $coreDir 'data.json')
    }
}

Describe 'Get-PocketCoreRequiredFile' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("req_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'flags a required BIOS file that is missing' {
        New-CoreWithData $script:root 'Test.NeoGeo' 'ng' @(
            @{ name = 'Cartridge'; required = $true;  filename = $null;             parameters = '0x1' }
            @{ name = 'BIOS';      required = $true;  filename = 'uni-bios_4_0.rom'; parameters = '0x2' }
        )
        $r = Get-PocketCoreRequiredFile -Root $script:root
        @($r).Count | Should -Be 1
        $r.Satisfied | Should -BeFalse
        $r.Missing | Should -Contain 'uni-bios_4_0.rom'
        # The required cartridge slot (no filename) is NOT treated as a required file.
        @($r.Required).Count | Should -Be 1
    }

    It 'is satisfied once the BIOS is placed in common (case-insensitive path)' {
        New-CoreWithData $script:root 'Test.NeoGeo' 'ng' @(
            @{ name = 'BIOS'; required = $true; filename = 'uni-bios_4_0.rom'; parameters = '0x2' }
        )
        $common = Join-Path $script:root 'Assets/ng/common'
        New-Item -ItemType Directory -Path $common -Force | Out-Null
        'bios' | Set-Content (Join-Path $common 'uni-bios_4_0.rom')
        (Get-PocketCoreRequiredFile -Root $script:root).Satisfied | Should -BeTrue
    }

    It 'ignores cores whose required slots have no fixed filename (pure cartridge cores)' {
        New-CoreWithData $script:root 'agg23.NES' 'nes' @(
            @{ name = 'Cartridge'; required = $true;  filename = $null;  parameters = '0x1' }
            @{ name = 'Palette';   required = $false; filename = 'p.pal'; parameters = '0x3' }
        )
        @(Get-PocketCoreRequiredFile -Root $script:root) | Should -HaveCount 0
    }

    It 'returns nothing for a card with no cores' {
        @(Get-PocketCoreRequiredFile -Root $script:root) | Should -HaveCount 0
    }
}
