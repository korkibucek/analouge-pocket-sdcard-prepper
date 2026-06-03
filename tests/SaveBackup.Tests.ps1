BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Backup-PocketSaves / Restore-PocketSaves' {
    BeforeEach {
        $script:card = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_card_" + [System.IO.Path]::GetRandomFileName())
        $script:dest = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_bak_"  + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path (Join-Path $script:card 'Saves/gb/common') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:card 'Memories') -Force | Out-Null
        'save1' | Set-Content (Join-Path $script:card 'Saves/gb/common/game.sav')
        'mem'   | Set-Content (Join-Path $script:card 'Memories/m.bin')
    }
    AfterEach { Remove-Item $script:card, $script:dest -Recurse -Force -ErrorAction SilentlyContinue }

    It 'backs up Saves only by default' {
        $r = Backup-PocketSaves -Root $script:card -Destination $script:dest -Stamp 'test'
        $r.FileCount | Should -Be 1
        (Test-Path (Join-Path $r.Destination 'Saves/gb/common/game.sav')) | Should -BeTrue
        (Test-Path (Join-Path $r.Destination 'Memories/m.bin')) | Should -BeFalse
    }
    It 'includes Memories when asked' {
        $r = Backup-PocketSaves -Root $script:card -Destination $script:dest -Stamp 'test' -IncludeMemories
        $r.FileCount | Should -Be 2
    }
    It 'DryRun copies nothing' {
        $r = Backup-PocketSaves -Root $script:card -Destination $script:dest -Stamp 'test' -DryRun
        $r.DryRun | Should -BeTrue
        (Test-Path $r.Destination) | Should -BeFalse
    }
    It 'restores onto a fresh card and skips existing unless -Overwrite' {
        $b = Backup-PocketSaves -Root $script:card -Destination $script:dest -Stamp 'test'
        $fresh = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_fresh_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $fresh -Force | Out-Null
        $r1 = Restore-PocketSaves -Root $fresh -Source $b.Destination
        $r1.RestoredCount | Should -Be 1
        (Test-Path (Join-Path $fresh 'Saves/gb/common/game.sav')) | Should -BeTrue
        $r2 = Restore-PocketSaves -Root $fresh -Source $b.Destination
        $r2.SkippedCount | Should -Be 1
        $r2.RestoredCount | Should -Be 0
        Remove-Item $fresh -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Saves API routes' {
    It 'POST /api/saves/backup requires a destination' {
        $state = @{ Root = (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())); IsTestMode = $true }
        New-Item -ItemType Directory -Path $state.Root -Force | Out-Null
        $r = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/saves/backup' -Body ([pscustomobject]@{}) -State $s }
        $r.Status | Should -Be 400
        Remove-Item $state.Root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
