BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Test-PocketCardEmpty' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_empty_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach {
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reports an empty folder as empty' {
        (Test-PocketCardEmpty -Root $script:root).IsEmpty | Should -BeTrue
    }

    It 'ignores benign OS entries' {
        New-Item -ItemType Directory -Path (Join-Path $script:root 'System Volume Information') | Out-Null
        New-Item -ItemType File -Path (Join-Path $script:root '.DS_Store') | Out-Null
        $v = Test-PocketCardEmpty -Root $script:root
        $v.IsEmpty | Should -BeTrue
        $v.IgnoredCount | Should -Be 2
    }

    It 'reports user content as not empty' {
        New-Item -ItemType File -Path (Join-Path $script:root 'mygame.gb') | Out-Null
        $v = Test-PocketCardEmpty -Root $script:root
        $v.IsEmpty | Should -BeFalse
        $v.Entries | Should -Contain 'mygame.gb'
    }

    It 'throws on a missing root' {
        { Test-PocketCardEmpty -Root (Join-Path $script:root 'does-not-exist') } | Should -Throw
    }
}
