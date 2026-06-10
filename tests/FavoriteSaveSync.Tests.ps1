BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    # Fabricate a card: original ROM in an organized subfolder + a favourited copy, with
    # the matching Saves-tree mirror locations.
    function New-FavCard {
        param($Root)
        $common = Join-Path $Root 'Assets/gb/common'
        New-Item -ItemType Directory -Path (Join-Path $common 'A-C') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $common '!Favorites') -Force | Out-Null
        'rom' | Set-Content (Join-Path $common 'A-C/Zelda.gb')
        'rom' | Set-Content (Join-Path $common '!Favorites/Zelda.gb')
        Save-PocketFavorite -Root $Root -PlatformId 'gb' -Names @('Zelda.gb') | Out-Null
        return $common
    }
    function Set-SaveAge { param($Path, [int]$MinutesAgo)
        (Get-Item -LiteralPath $Path).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-$MinutesAgo)
    }
}

Describe 'Sync-PocketFavoriteSave (copy mode: -NoSymlink, like a FAT card)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fss_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        New-FavCard $script:root | Out-Null
        $script:oSave = Join-Path $script:root 'Saves/gb/common/A-C/Zelda.sav'
        $script:fSave = Join-Path $script:root 'Saves/gb/common/!Favorites/Zelda.sav'
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'copies the original save to the favourite when only the original has one' {
        New-Item -ItemType Directory -Path (Split-Path $script:oSave) -Force | Out-Null
        'progress-orig' | Set-Content $script:oSave
        $r = Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb' -NoSymlink
        $r.CopiedToFavorite | Should -Be 1
        Get-Content $script:fSave | Should -Be 'progress-orig'
    }

    It 'seeds the original (master) when only the favourite has a save' {
        New-Item -ItemType Directory -Path (Split-Path $script:fSave) -Force | Out-Null
        'progress-fav' | Set-Content $script:fSave
        $r = Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb' -NoSymlink
        $r.CopiedToOriginal | Should -Be 1
        Get-Content $script:oSave | Should -Be 'progress-fav'
    }

    It 'newest wins: favourite newer -> original updated, old original backed up' {
        New-Item -ItemType Directory -Path (Split-Path $script:oSave) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $script:fSave) -Force | Out-Null
        'old-orig' | Set-Content $script:oSave; Set-SaveAge $script:oSave 60
        'new-fav'  | Set-Content $script:fSave
        $r = Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb' -NoSymlink
        Get-Content $script:oSave | Should -Be 'new-fav'
        $r.BackupCount | Should -BeGreaterOrEqual 1
        # The overwritten original's progress is preserved in the backup folder.
        $bak = Get-ChildItem (Join-Path $script:root 'pocketprep/save-backups/gb') -File
        @($bak | Where-Object { (Get-Content $_.FullName) -eq 'old-orig' }).Count | Should -BeGreaterOrEqual 1
    }

    It 'newest wins: original newer -> favourite updated, old favourite backed up' {
        New-Item -ItemType Directory -Path (Split-Path $script:oSave) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $script:fSave) -Force | Out-Null
        'new-orig' | Set-Content $script:oSave
        'old-fav'  | Set-Content $script:fSave; Set-SaveAge $script:fSave 60
        $r = Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb' -NoSymlink
        Get-Content $script:fSave | Should -Be 'new-orig'
        $r.BackupCount | Should -BeGreaterOrEqual 1
    }

    It 'folds an unfavourited save back to the original and removes the mirror' {
        New-Item -ItemType Directory -Path (Split-Path $script:fSave) -Force | Out-Null
        'fav-progress' | Set-Content $script:fSave
        Save-PocketFavorite -Root $script:root -PlatformId 'gb' -Names @() | Out-Null   # untag
        $r = Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb' -NoSymlink
        $r.FoldedBackCount | Should -Be 1
        Get-Content $script:oSave | Should -Be 'fav-progress'   # progress not lost
        (Test-Path $script:fSave) | Should -BeFalse              # stale mirror removed
    }

    It 'is idempotent and DryRun changes nothing' {
        New-Item -ItemType Directory -Path (Split-Path $script:oSave) -Force | Out-Null
        'p' | Set-Content $script:oSave
        Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb' -NoSymlink | Out-Null
        $r2 = Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb' -NoSymlink
        ($r2.CopiedToFavorite + $r2.CopiedToOriginal + $r2.FoldedBackCount) | Should -Be 0

        'newer' | Set-Content $script:oSave
        $dr = Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb' -NoSymlink -DryRun
        $dr.DryRun | Should -BeTrue
        Get-Content $script:fSave | Should -Be 'p'   # untouched by dry-run
    }
}

Describe 'Sync-PocketFavoriteSave (symlink mode, where supported)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fsl_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        New-FavCard $script:root | Out-Null
        $script:oSave = Join-Path $script:root 'Saves/gb/common/A-C/Zelda.sav'
        $script:fSave = Join-Path $script:root 'Saves/gb/common/!Favorites/Zelda.sav'
        New-Item -ItemType Directory -Path (Split-Path $script:oSave) -Force | Out-Null
        'master' | Set-Content $script:oSave
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'links the favourite save to the original (single master file)' {
        if (-not (Test-PocketSymlinkSupport -Root $script:root)) {
            Set-ItResult -Skipped -Because 'filesystem does not support symlinks here'
            return
        }
        $r = Sync-PocketFavoriteSave -Root $script:root -PlatformId 'gb'
        $r.Method | Should -Be 'symlink'
        $r.LinkedCount | Should -Be 1
        (Get-Item $script:fSave).LinkType | Should -Be 'SymbolicLink'
        # Writing through the favourite's path updates the master file.
        'played-via-favourite' | Set-Content $script:fSave
        Get-Content $script:oSave | Should -Be 'played-via-favourite'
    }
}
