BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    function New-GbRoms {
        param($Root, [string[]]$Names)
        $common = Join-Path $Root 'Assets/gb/common'
        New-Item -ItemType Directory -Path $common -Force | Out-Null
        foreach ($n in $Names) { "rom-$n" | Set-Content (Join-Path $common $n) }
        return $common
    }
}

Describe 'Get/Save-PocketFavorite' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fav_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'returns empty when no favourites are saved' {
        $f = Get-PocketFavorite -Root $script:root
        $f.Exists | Should -BeFalse
        @($f.Platforms).Count | Should -Be 0
        @(Get-PocketFavorite -Root $script:root -PlatformId 'gb').Count | Should -Be 0
    }

    It 'saves and reads back per-platform favourites (deduped)' {
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('A.gb', 'B.gb', 'A.gb') | Out-Null
        Save-PocketFavorite -Root $script:root -PlatformId 'nes' -Names @('X.nes') | Out-Null
        @(Get-PocketFavorite -Root $script:root -PlatformId 'gb') | Should -HaveCount 2
        @(Get-PocketFavorite -Root $script:root -PlatformId 'nes') | Should -Be @('X.nes')
        (Get-PocketFavorite -Root $script:root).Platforms.Count | Should -Be 2
    }

    It 'clearing a platform removes only that platform' {
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('A.gb') | Out-Null
        Save-PocketFavorite -Root $script:root -PlatformId 'nes' -Names @('X.nes') | Out-Null
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @() | Out-Null
        @(Get-PocketFavorite -Root $script:root -PlatformId 'gb') | Should -HaveCount 0
        @(Get-PocketFavorite -Root $script:root -PlatformId 'nes') | Should -HaveCount 1
    }
}

Describe 'Sync-PocketFavorite' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("favs_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:common = New-GbRoms $script:root @('Tetris.gb', 'Zelda.gb', 'Mario.gb')
        $script:favDir = Join-Path $script:common 'Favorites'
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'materialises favourites into the Favorites folder, original untouched' {
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('Tetris.gb', 'Zelda.gb') | Out-Null
        $r = Sync-PocketFavorite -Root $script:root -PlatformId 'gb'
        ($r.LinkedCount + $r.CopiedCount) | Should -Be 2
        $r.Method | Should -BeIn @('symlink', 'copy')
        (Test-Path (Join-Path $script:favDir 'Tetris.gb')) | Should -BeTrue
        # Original remains in the alphabetical (common) location.
        (Test-Path (Join-Path $script:common 'Tetris.gb')) | Should -BeTrue
    }

    It 'removes a stale favourite when it is untagged, leaving the original' {
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('Tetris.gb', 'Zelda.gb') | Out-Null
        Sync-PocketFavorite -Root $script:root -PlatformId 'gb' | Out-Null
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('Tetris.gb') | Out-Null   # untag Zelda
        $r = Sync-PocketFavorite -Root $script:root -PlatformId 'gb'
        $r.RemovedCount | Should -Be 1
        (Test-Path (Join-Path $script:favDir 'Zelda.gb')) | Should -BeFalse
        (Test-Path (Join-Path $script:common 'Zelda.gb')) | Should -BeTrue   # original kept
    }

    It 'is idempotent (re-sync adds/removes nothing)' {
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('Mario.gb') | Out-Null
        Sync-PocketFavorite -Root $script:root -PlatformId 'gb' | Out-Null
        $r2 = Sync-PocketFavorite -Root $script:root -PlatformId 'gb'
        ($r2.LinkedCount + $r2.CopiedCount) | Should -Be 0
        $r2.RemovedCount | Should -Be 0
    }

    It 'reports a favourite whose source is missing' {
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('Ghost.gb') | Out-Null
        $r = Sync-PocketFavorite -Root $script:root -PlatformId 'gb'
        $r.Missing | Should -Contain 'Ghost.gb'
    }

    It 'finds favourites even after the organizer moved them into subfolders' {
        # Organize into buckets, then favourite a ROM that now lives in a subfolder.
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 1
        Invoke-PocketRomOrganizePlan -Plan $plan | Out-Null
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('Zelda.gb') | Out-Null
        $r = Sync-PocketFavorite -Root $script:root -PlatformId 'gb'
        ($r.LinkedCount + $r.CopiedCount) | Should -Be 1
        (Test-Path (Join-Path $script:favDir 'Zelda.gb')) | Should -BeTrue
    }

    It 'organizer ignores the Favorites folder (does not re-bucket favourites)' {
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @('Tetris.gb') | Out-Null
        Sync-PocketFavorite -Root $script:root -PlatformId 'gb' | Out-Null
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 1
        # The 3 real ROMs are bucketed; the Favorites copy/link is not counted as a ROM.
        $plan.FileCount | Should -Be 3
        ($plan.Items.Source | Where-Object { $_ -match 'Favorites' }).Count | Should -Be 0
    }
}
