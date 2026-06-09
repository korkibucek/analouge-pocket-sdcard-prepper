BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    function New-Roms { param($Common, [string[]]$Names)
        New-Item -ItemType Directory -Path $Common -Force | Out-Null
        foreach ($n in $Names) { "rom-$n" | Set-Content (Join-Path $Common $n) }
    }
}

Describe 'Get-PocketRomRegionDuplicate' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("rd_" + [System.IO.Path]::GetRandomFileName())
        $script:common = Join-Path $script:root 'Assets/gb/common'
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'groups region variants and recommends keeping the preferred region' {
        New-Roms $script:common @('Sonic (USA).gb', 'Sonic (Europe).gb', 'Sonic (Japan).gb')
        $r = Get-PocketRomRegionDuplicate -Root $script:root -PlatformId 'gb' -RegionOrder @('EU','USA','JPN','Global')
        @($r.Sets).Count | Should -Be 1
        $r.Sets[0].Keep.Name | Should -Be 'Sonic (Europe).gb'        # EU preferred
        @($r.Sets[0].Remove.Name) | Should -Contain 'Sonic (USA).gb'
        @($r.Sets[0].Remove.Name) | Should -Contain 'Sonic (Japan).gb'
        $r.RemoveCount | Should -Be 2
    }

    It 'respects a different region order (USA first)' {
        New-Roms $script:common @('Mario (USA).gb', 'Mario (Europe).gb')
        $r = Get-PocketRomRegionDuplicate -Root $script:root -PlatformId 'gb' -RegionOrder @('USA','EU','JPN','Global')
        $r.Sets[0].Keep.Name | Should -Be 'Mario (USA).gb'
    }

    It 'does NOT collapse different discs of the same game' {
        New-Roms $script:common @('FF7 (USA) (Disc 1).gb', 'FF7 (USA) (Disc 2).gb')
        (Get-PocketRomRegionDuplicate -Root $script:root -PlatformId 'gb').RemoveCount | Should -Be 0
    }

    It 'ignores region-less files' {
        New-Roms $script:common @('Homebrew Demo.gb', 'Another Homebrew.gb')
        $r = Get-PocketRomRegionDuplicate -Root $script:root -PlatformId 'gb'
        @($r.Sets) | Should -HaveCount 0
        $r.RemoveCount | Should -Be 0
    }

    It 'maps PAL/NTSC-J synonyms to EU/JPN' {
        New-Roms $script:common @('Game (PAL).gb', 'Game (NTSC-J).gb')
        $r = Get-PocketRomRegionDuplicate -Root $script:root -PlatformId 'gb' -RegionOrder @('JPN','EU','USA','Global')
        $r.Sets[0].Keep.Name | Should -Be 'Game (NTSC-J).gb'        # JPN preferred
    }
}

Describe 'Invoke-PocketRomRegionDedupe' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("rdx_" + [System.IO.Path]::GetRandomFileName())
        $script:common = Join-Path $script:root 'Assets/gb/common'
        New-Roms $script:common @('Sonic (USA).gb', 'Sonic (Europe).gb', 'Sonic (Japan).gb')
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'quarantines the non-preferred copies (reversible), keeping the preferred one' {
        $r = Invoke-PocketRomRegionDedupe -Root $script:root -PlatformId 'gb' -RegionOrder @('EU','USA','JPN','Global')
        $r.MovedCount | Should -Be 2
        (Test-Path (Join-Path $script:common 'Sonic (Europe).gb')) | Should -BeTrue    # kept in place
        (Test-Path (Join-Path $script:common 'Sonic (USA).gb')) | Should -BeFalse      # moved out
        # Moved to the quarantine (outside Assets), nothing deleted.
        (Test-Path (Join-Path $r.QuarantineDir 'Sonic (USA).gb')) | Should -BeTrue
        (Test-Path (Join-Path $r.QuarantineDir 'Sonic (Japan).gb')) | Should -BeTrue
    }

    It '-DryRun moves nothing' {
        $r = Invoke-PocketRomRegionDedupe -Root $script:root -PlatformId 'gb' -DryRun
        $r.DryRun | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:common -File).Count | Should -Be 3
    }
}
