BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    function New-StateCard {
        param($Root)
        $dir = Join-Path $Root 'Memories/Save States/gb'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        # Five numbered states for one game, oldest first.
        1..5 | ForEach-Object {
            $f = Join-Path $dir "Zelda-$_.sta"
            "state$_" | Set-Content $f
            (Get-Item $f).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(-(10 - $_))
        }
        # A singleton state with no numeric suffix (own group).
        'solo' | Set-Content (Join-Path $dir 'Tetris.sta')
        # Non-save-state user data that must NEVER be touched.
        New-Item -ItemType Directory -Path (Join-Path $Root 'Memories/Screenshots') -Force | Out-Null
        'shot' | Set-Content (Join-Path $Root 'Memories/Screenshots/pic.png')
        New-Item -ItemType Directory -Path (Join-Path $Root 'Assets/gb/common') -Force | Out-Null
        'rom' | Set-Content (Join-Path $Root 'Assets/gb/common/Zelda.gb')
        return $dir
    }
}

Describe 'Invoke-PocketSaveStatePrune' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("ssp_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:dir = New-StateCard $script:root
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'keeps the N newest per game, backs up before deleting, touches nothing else' {
        $r = Invoke-PocketSaveStatePrune -Root $script:root -KeepPerGame 2
        $r.DeleteCount | Should -Be 3
        # The two NEWEST numbered states survive; the singleton is its own group and survives.
        (Test-Path (Join-Path $script:dir 'Zelda-5.sta')) | Should -BeTrue
        (Test-Path (Join-Path $script:dir 'Zelda-4.sta')) | Should -BeTrue
        (Test-Path (Join-Path $script:dir 'Zelda-1.sta')) | Should -BeFalse
        (Test-Path (Join-Path $script:dir 'Tetris.sta')) | Should -BeTrue
        # Mandatory backup zip holds every deleted file (recoverable).
        $r.BackupZip | Should -Not -BeNullOrEmpty
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($r.BackupZip)
        try { $zip.Entries.Count | Should -Be 3 } finally { $zip.Dispose() }
        # Everything outside Memories/Save States is untouched.
        (Test-Path (Join-Path $script:root 'Memories/Screenshots/pic.png')) | Should -BeTrue
        (Test-Path (Join-Path $script:root 'Assets/gb/common/Zelda.gb')) | Should -BeTrue
    }

    It 'OlderThanDays deletes only states past the cutoff' {
        $r = Invoke-PocketSaveStatePrune -Root $script:root -OlderThanDays 7
        # Ages are 9,8,7,6,5 days for Zelda-1..5 (the 7-day one is marginally past the
        # cutoff computed at prune time); Tetris is fresh.
        $r.DeleteCount | Should -Be 3   # 9, 8 and 7 days old
        (Test-Path (Join-Path $script:dir 'Zelda-1.sta')) | Should -BeFalse
        (Test-Path (Join-Path $script:dir 'Zelda-3.sta')) | Should -BeFalse
        (Test-Path (Join-Path $script:dir 'Zelda-4.sta')) | Should -BeTrue
    }

    It 'with both policies a file must match BOTH to be deleted' {
        # KeepPerGame 1 alone would delete Zelda-1..4; the age filter restricts to >8.5 days.
        $r = Invoke-PocketSaveStatePrune -Root $script:root -KeepPerGame 1 -OlderThanDays 8 -DryRun
        $r.DeleteCount | Should -Be 2   # only Zelda-1 (9d) and Zelda-2 (8d... strictly older than 8d -> 9d & ~8.0? ages 9,8 -> 9d qualifies; 8d boundary)
        $r.Deleted | Should -Contain 'gb/Zelda-1.sta'
    }

    It 'refuses to run without any policy' {
        { Invoke-PocketSaveStatePrune -Root $script:root } | Should -Throw '*without a policy*'
    }

    It 'DryRun deletes nothing and writes no backup' {
        $r = Invoke-PocketSaveStatePrune -Root $script:root -KeepPerGame 1 -DryRun
        $r.DryRun | Should -BeTrue
        $r.DeleteCount | Should -Be 4
        $r.BackupZip | Should -BeNullOrEmpty
        @(Get-ChildItem $script:dir -File).Count | Should -Be 6
        (Test-Path (Join-Path $script:root 'pocketprep/save-backups')) | Should -BeFalse
    }

    It 'a pruned state is recoverable from the backup zip' {
        $r = Invoke-PocketSaveStatePrune -Root $script:root -KeepPerGame 2
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($r.BackupZip)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -like '*Zelda-1.sta' }
            $entry | Should -Not -BeNullOrEmpty
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try { $reader.ReadToEnd().Trim() | Should -Be 'state1' } finally { $reader.Dispose() }
        } finally { $zip.Dispose() }
    }
}
