BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'New-PocketFolderStructure' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_folders_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach {
        Remove-Item -LiteralPath $script:root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'creates the verified openFPGA folders' {
        $r = New-PocketFolderStructure -Root $script:root
        foreach ($f in 'Assets','Cores','Saves','Settings','System','Memories','Presets','GB Studio','Platforms') {
            (Test-Path (Join-Path $script:root $f)) | Should -BeTrue
        }
        $r.Created | Should -Contain 'Assets'
    }

    It 'is idempotent and reports existing folders' {
        New-PocketFolderStructure -Root $script:root | Out-Null
        $r = New-PocketFolderStructure -Root $script:root
        $r.Created.Count | Should -Be 0
        $r.Existing | Should -Contain 'Cores'
    }

    It 'DryRun creates nothing' {
        $r = New-PocketFolderStructure -Root $script:root -DryRun
        $r.DryRun | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Assets')) | Should -BeFalse
        $r.Created | Should -Contain 'Assets'
    }
}
