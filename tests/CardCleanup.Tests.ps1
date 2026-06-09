BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:cm = Join-Path $repo 'manifests/cores.json'

    function New-Core { param($Root, $Identifier, $PlatformId)
        $dir = Join-Path $Root "Cores/$Identifier"; New-Item -ItemType Directory -Path $dir -Force | Out-Null
        @{ core = @{ metadata = @{ shortname=$Identifier; author='x'; version='1'; platform_ids=@($PlatformId) } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $dir 'core.json')
    }
}

Describe 'Get-PocketCardCleanup' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("cu_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'lists empty dirs, probe dirs, orphan assets and unmanaged cores' {
        # An installed core providing 'gb'; a ROM for an orphan platform 'zzz' with no core.
        New-Core $script:root 'Some.Unmanaged' 'gb'
        New-Item -ItemType Directory -Path (Join-Path $script:root 'Assets/zzz/common') -Force | Out-Null
        'rom' | Set-Content (Join-Path $script:root 'Assets/zzz/common/game.zzz')
        New-Item -ItemType Directory -Path (Join-Path $script:root 'Assets/gb/common/EmptyBucket') -Force | Out-Null   # depth>=2 empty
        New-Item -ItemType Directory -Path (Join-Path $script:root '.pp-symlink-probe-abc') -Force | Out-Null

        $c = Get-PocketCardCleanup -Root $script:root -CoresManifest $script:cm
        $c.UnmanagedCores | Should -Contain 'Some.Unmanaged'             # not in catalog
        ($c.OrphanAssetPlatforms | ForEach-Object { $_.PlatformId }) | Should -Contain 'zzz'
        ($c.OrphanAssetPlatforms | ForEach-Object { $_.PlatformId }) | Should -Not -Contain 'gb'   # provided by a core
        @($c.EmptyDirs) | Should -Contain (Join-Path $script:root 'Assets/gb/common/EmptyBucket')
        @($c.ProbeDirs).Count | Should -Be 1
    }

    It 'does not list a top-level empty folder' {
        New-Item -ItemType Directory -Path (Join-Path $script:root 'Saves') -Force | Out-Null   # empty top-level
        $c = Get-PocketCardCleanup -Root $script:root
        @($c.EmptyDirs) | Should -Not -Contain (Join-Path $script:root 'Saves')
    }
}

Describe 'Invoke-PocketCardCleanup' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("cux_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path (Join-Path $script:root 'Assets/gb/common/EmptyBucket') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:root '.pp-symlink-probe-xyz') -Force | Out-Null
        'rom' | Set-Content (Join-Path $script:root 'Assets/gb/common/keep.gb')   # a real ROM (must survive)
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'removes empty + temp dirs but never a ROM' {
        $r = Invoke-PocketCardCleanup -Root $script:root
        $r.RemovedCount | Should -BeGreaterOrEqual 2
        (Test-Path (Join-Path $script:root 'Assets/gb/common/EmptyBucket')) | Should -BeFalse
        (Test-Path (Join-Path $script:root '.pp-symlink-probe-xyz')) | Should -BeFalse
        (Test-Path (Join-Path $script:root 'Assets/gb/common/keep.gb')) | Should -BeTrue   # ROM kept
    }

    It 'DryRun removes nothing' {
        $r = Invoke-PocketCardCleanup -Root $script:root -DryRun
        $r.DryRun | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Assets/gb/common/EmptyBucket')) | Should -BeTrue
    }
}
