BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Clear-PocketCard (guarded)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_clean_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path (Join-Path $script:root 'Assets') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:root 'System Volume Information') -Force | Out-Null
        'rom' | Set-Content (Join-Path $script:root 'game.gb')
        # A provider that reports this temp root as a removable card.
        $r = $script:root
        $script:removableProvider = [scriptblock]::Create("@([pscustomobject]@{ DriveLetter='$r'; RootPath='$r'; Label='POCKET'; FileSystem='exFAT'; SizeBytes=64GB; FreeBytes=64GB; IsRemovable=`$true; BusType='usb'; MediaType='' })")
        $script:fixedProvider = [scriptblock]::Create("@([pscustomobject]@{ DriveLetter='$r'; RootPath='$r'; Label='BACKUP'; FileSystem='exFAT'; SizeBytes=2TB; FreeBytes=1TB; IsRemovable=`$false; BusType='sata'; MediaType='' })")
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'refuses when the target is not a detected removable volume' {
        { Clear-PocketCard -Root $script:root -ConfirmToken 'POCKET' -DataProvider { @() } } | Should -Throw
        (Test-Path (Join-Path $script:root 'game.gb')) | Should -BeTrue
    }

    It 'refuses a non-removable (fixed) volume without override' {
        { Clear-PocketCard -Root $script:root -ConfirmToken 'BACKUP' -DataProvider $script:fixedProvider } | Should -Throw
        (Test-Path (Join-Path $script:root 'game.gb')) | Should -BeTrue
    }

    It 'refuses when the confirmation token does not match' {
        { Clear-PocketCard -Root $script:root -ConfirmToken 'WRONG' -DataProvider $script:removableProvider } | Should -Throw
        (Test-Path (Join-Path $script:root 'game.gb')) | Should -BeTrue
    }

    It 'DryRun lists what would be removed but deletes nothing' {
        $r = Clear-PocketCard -Root $script:root -ConfirmToken 'POCKET' -DataProvider $script:removableProvider -DryRun
        $r.DryRun | Should -BeTrue
        $r.Removed | Should -Contain 'game.gb'
        (Test-Path (Join-Path $script:root 'game.gb')) | Should -BeTrue
    }

    It 'with a matching token, removes contents but keeps the root and OS entries' {
        $r = Clear-PocketCard -Root $script:root -ConfirmToken 'POCKET' -DataProvider $script:removableProvider
        $r.RemovedCount | Should -BeGreaterThan 0
        (Test-Path (Join-Path $script:root 'game.gb')) | Should -BeFalse
        (Test-Path (Join-Path $script:root 'Assets')) | Should -BeFalse
        (Test-Path $script:root) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'System Volume Information')) | Should -BeTrue   # OS entry skipped
    }

    It 'accepts the root path itself as the confirmation token' {
        { Clear-PocketCard -Root $script:root -ConfirmToken $script:root -DataProvider $script:removableProvider -DryRun } | Should -Not -Throw
    }
}
