BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:sm = Join-Path $repo 'manifests/systems.json'

    # An installed core declaring required files: one common slot, one core-specific slot.
    function New-BiosCore {
        param($Root)
        $dir = Join-Path $Root 'Cores/Test.NeoGeo'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        @{ core = @{ metadata = @{ shortname='NG'; author='x'; version='1'; platform_ids=@('ng') } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $dir 'core.json')
        @{ data = @{ data_slots = @(
            @{ name='BIOS'; required=$true; filename='uni-bios_4_0.rom' }
            @{ name='LO';   required=$true; filename='000-lo.lo'; core_specific_file=$true }
        ) } } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $dir 'data.json')
    }
}

Describe 'Install-PocketBiosFile' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("bi_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:src = Join-Path ([System.IO.Path]::GetTempPath()) ("bisrc_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:src -Force | Out-Null
        'bios-bytes' | Set-Content (Join-Path $script:src 'my-weirdly-named-bios.bin')
        New-BiosCore $script:root
    }
    AfterEach { Remove-Item $script:root, $script:src -Recurse -Force -ErrorAction SilentlyContinue }

    It 'places a user file into a declared common slot, renamed to the exact filename' {
        $r = Install-PocketBiosFile -Root $script:root -PlatformId 'ng' -FileName 'uni-bios_4_0.rom' `
            -SourceFile (Join-Path $script:src 'my-weirdly-named-bios.bin')
        $r.Installed | Should -BeTrue
        $r.Renamed | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Assets/ng/common/uni-bios_4_0.rom')) | Should -BeTrue
        # The detector now reports that slot satisfied.
        $req = Get-PocketCoreRequiredFile -Root $script:root
        ($req.Required | Where-Object Filename -eq 'uni-bios_4_0.rom').Found | Should -BeTrue
    }

    It 'places a core-specific slot file into the core-specific folder' {
        $r = Install-PocketBiosFile -Root $script:root -PlatformId 'ng' -FileName '000-lo.lo' `
            -SourceFile (Join-Path $script:src 'my-weirdly-named-bios.bin')
        $r.Installed | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Assets/ng/Test.NeoGeo/000-lo.lo')) | Should -BeTrue
    }

    It 'satisfies a manifest-declared system BIOS even with no core installed' {
        $bare = Join-Path ([System.IO.Path]::GetTempPath()) ("bib_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $bare -Force | Out-Null
        try {
            $r = Install-PocketBiosFile -Root $bare -PlatformId 'ng' -FileName 'neogeo.zip' `
                -SourceFile (Join-Path $script:src 'my-weirdly-named-bios.bin') -SystemsManifest $script:sm
            $r.Installed | Should -BeTrue
            (Test-Path (Join-Path $bare 'Assets/ng/common/neogeo.zip')) | Should -BeTrue
            (Get-PocketBiosStatus -Root $bare -SystemsManifest $script:sm -SystemId 'neogeo').Satisfied | Should -BeTrue
        } finally { Remove-Item $bare -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a target that no core or system declares' {
        { Install-PocketBiosFile -Root $script:root -PlatformId 'gb' -FileName 'totally-made-up.rom' `
            -SourceFile (Join-Path $script:src 'my-weirdly-named-bios.bin') } | Should -Throw '*not a BIOS/required file*'
    }

    It 'does not overwrite an existing file unless -Overwrite' {
        $dest = Join-Path $script:root 'Assets/ng/common/uni-bios_4_0.rom'
        New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
        'old' | Set-Content $dest
        $r = Install-PocketBiosFile -Root $script:root -PlatformId 'ng' -FileName 'uni-bios_4_0.rom' `
            -SourceFile (Join-Path $script:src 'my-weirdly-named-bios.bin')
        $r.Installed | Should -BeFalse
        Get-Content $dest | Should -Be 'old'
        $r2 = Install-PocketBiosFile -Root $script:root -PlatformId 'ng' -FileName 'uni-bios_4_0.rom' `
            -SourceFile (Join-Path $script:src 'my-weirdly-named-bios.bin') -Overwrite
        $r2.Installed | Should -BeTrue
        Get-Content $dest | Should -Be 'bios-bytes'
    }

    It 'DryRun writes nothing; missing source throws' {
        $r = Install-PocketBiosFile -Root $script:root -PlatformId 'ng' -FileName 'uni-bios_4_0.rom' `
            -SourceFile (Join-Path $script:src 'my-weirdly-named-bios.bin') -DryRun
        $r.DryRun | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Assets/ng/common/uni-bios_4_0.rom')) | Should -BeFalse
        { Install-PocketBiosFile -Root $script:root -PlatformId 'ng' -FileName 'uni-bios_4_0.rom' `
            -SourceFile (Join-Path $script:src 'nope.bin') } | Should -Throw '*not found*'
    }
}
