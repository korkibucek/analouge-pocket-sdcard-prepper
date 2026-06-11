BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:sm = Join-Path $repo 'manifests/systems.json'
    $script:cm = Join-Path $repo 'manifests/cores.json'

    function Get-Check { param($Report, $Name) $Report.Checks | Where-Object Name -eq $Name }
}

Describe 'Get-PocketHealthReport' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("hc_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'warns about missing firmware on an empty card and stays read-only' {
        $before = @(Get-ChildItem -LiteralPath $script:root -Recurse -Force).Count
        $r = Get-PocketHealthReport -Root $script:root -SystemsManifest $script:sm -CoresManifest $script:cm
        (Get-Check $r 'Firmware').Status | Should -Be 'warn'
        $r.Overall | Should -BeIn @('warn', 'fail')
        @(Get-ChildItem -LiteralPath $script:root -Recurse -Force).Count | Should -Be $before   # nothing written
    }

    It 'reports ok firmware when present, and flags a broken core as fail' {
        'fw' | Set-Content (Join-Path $script:root 'pocket_firmware_2_5.bin')
        $cd = Join-Path $script:root 'Cores/broken.Core'; New-Item -ItemType Directory $cd -Force | Out-Null
        @{ core = @{ metadata = @{ shortname='B'; author='x'; version='1'; platform_ids=@('gb') } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cd 'core.json')   # missing data/video/input
        $r = Get-PocketHealthReport -Root $script:root -SystemsManifest $script:sm -CoresManifest $script:cm
        (Get-Check $r 'Firmware').Status | Should -Be 'ok'
        (Get-Check $r 'Core integrity').Status | Should -Be 'fail'
        $r.Overall | Should -Be 'fail'
    }

    It 'flags a directory exceeding the per-folder limit (counted per directory)' {
        $common = Join-Path $script:root 'Assets/gb/common'
        New-Item -ItemType Directory -Path (Join-Path $common 'A-C') -Force | Out-Null
        1..4 | ForEach-Object { 'r' | Set-Content (Join-Path $common "g$_.gb") }            # 4 in common
        1..3 | ForEach-Object { 'r' | Set-Content (Join-Path $common "A-C/a$_.gb") }        # 3 in bucket
        # Limit 3: only the common dir (4 files) exceeds; the bucket (3) does not.
        $r = Get-PocketHealthReport -Root $script:root -SystemsManifest $script:sm -CoresManifest $script:cm -MaxPerFolder 3
        $c = Get-Check $r 'Per-folder game limit'
        $c.Status | Should -Be 'warn'
        $c.Detail | Should -Match '1 folder'
        # With the real default the same card is fine.
        (Get-Check (Get-PocketHealthReport -Root $script:root -SystemsManifest $script:sm -CoresManifest $script:cm) 'Per-folder game limit').Status | Should -Be 'ok'
    }

    It 'warns about overlong filenames and missing BIOS' {
        $common = Join-Path $script:root 'Assets/ng/common'
        New-Item -ItemType Directory -Path $common -Force | Out-Null
        'r' | Set-Content (Join-Path $common (('L' * 120) + '.zip'))
        # ng is folder-format: it only counts as "in use" with a game folder present.
        New-Item -ItemType Directory -Path (Join-Path $common 'mslug4') -Force | Out-Null
        'x' | Set-Content (Join-Path $common 'mslug4/prom')
        $r = Get-PocketHealthReport -Root $script:root -SystemsManifest $script:sm -CoresManifest $script:cm
        (Get-Check $r 'Filename length').Status | Should -Be 'warn'
        $bios = Get-Check $r 'BIOS / required files'
        $bios.Status | Should -Be 'warn'
        $bios.Detail | Should -Match 'uni-bios_4_0\.rom'   # manifest-declared Neo Geo BIOS missing
    }

    It 'warns about ROMs whose platform has no installed core' {
        $common = Join-Path $script:root 'Assets/zzz/common'
        New-Item -ItemType Directory -Path $common -Force | Out-Null
        'r' | Set-Content (Join-Path $common 'game.zzz')
        $r = Get-PocketHealthReport -Root $script:root -SystemsManifest $script:sm -CoresManifest $script:cm
        $c = Get-Check $r 'ROMs without a core'
        $c.Status | Should -Be 'warn'
        $c.Detail | Should -Match 'zzz'
    }

    It 'reports overall ok for a healthy card' {
        'fw' | Set-Content (Join-Path $script:root 'pocket_firmware_2_5.bin')
        $r = Get-PocketHealthReport -Root $script:root -SystemsManifest $script:sm -CoresManifest $script:cm
        @($r.Checks | Where-Object Status -in @('warn', 'fail')).Count | Should -Be 0
        $r.Overall | Should -BeIn @('ok', 'info')
    }
}
