BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:gb = Get-PocketSystem -Path (Join-Path $repo 'manifests/systems.json') -Id 'gb'
}

Describe 'New-PocketRomCopyPlan' {
    BeforeEach {
        $script:src  = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_src_"  + [System.IO.Path]::GetRandomFileName())
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_root_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:src  -Force | Out-Null
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        'a' | Set-Content (Join-Path $script:src 'game1.gb')
        'b' | Set-Content (Join-Path $script:src 'game2.gb')
        'c' | Set-Content (Join-Path $script:src 'notes.txt')
        'd' | Set-Content (Join-Path $script:src 'photo.png')
    }
    AfterEach {
        Remove-Item $script:src,$script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'matches only supported extensions' {
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root
        $plan.FileCount | Should -Be 2
        $plan.SkippedNonMatching | Should -Be 2
    }

    It 'targets Assets/<platformId>/common' {
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root
        $plan.Destination | Should -Match 'Assets[\\/]gb[\\/]common$'
    }

    It 'flattens by default' {
        $sub = Join-Path $script:src 'sub'
        New-Item -ItemType Directory -Path $sub | Out-Null
        'e' | Set-Content (Join-Path $sub 'game3.gb')
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root -Recurse
        $plan.Flatten | Should -BeTrue
        ($plan.Items | Where-Object { $_.RelativePath -eq 'game3.gb' }) | Should -Not -BeNullOrEmpty
    }

    It 'throws on a missing source folder' {
        { New-PocketRomCopyPlan -System $script:gb -SourceFolder (Join-Path $script:src 'nope') -Root $script:root } | Should -Throw
    }
}

Describe 'Invoke-PocketRomCopyPlan' {
    BeforeEach {
        $script:src  = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_src_"  + [System.IO.Path]::GetRandomFileName())
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_root_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:src  -Force | Out-Null
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        'a' | Set-Content (Join-Path $script:src 'game1.gb')
        'b' | Set-Content (Join-Path $script:src 'game2.gb')
        $script:plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root
    }
    AfterEach {
        Remove-Item $script:src,$script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'DryRun copies nothing to disk' {
        $r = Invoke-PocketRomCopyPlan -Plan $script:plan -DryRun
        $r.DryRun | Should -BeTrue
        (Test-Path $script:plan.Destination) | Should -BeFalse
    }

    It 'actually copies files to the destination' {
        $r = Invoke-PocketRomCopyPlan -Plan $script:plan
        $r.CopiedCount | Should -Be 2
        (Test-Path (Join-Path $script:plan.Destination 'game1.gb')) | Should -BeTrue
    }

    It 'skips existing files unless -Overwrite' {
        Invoke-PocketRomCopyPlan -Plan $script:plan | Out-Null
        $r2 = Invoke-PocketRomCopyPlan -Plan $script:plan
        $r2.SkippedCount | Should -Be 2
        $r2.CopiedCount | Should -Be 0
    }

    It 'returns exactly one result object even with a -Logger (no log-line pollution)' {
        $logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_rl_" + [System.IO.Path]::GetRandomFileName() + '.log')
        $logger = New-PocketLogger -Path $logPath
        $out = Invoke-PocketRomCopyPlan -Plan $script:plan -Logger $logger
        @($out).Count | Should -Be 1
        $out.PSObject.TypeNames | Should -Contain 'PocketPrep.RomCopyResult'
        $out.CopiedCount | Should -Be 2
        Remove-Item $logPath -Force -ErrorAction SilentlyContinue
    }
}
