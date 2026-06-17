BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:repo = $repo
}

Describe 'Memory Cleaner engine' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("mc_" + [System.IO.Path]::GetRandomFileName())
        $script:states = Join-Path (Join-Path $script:root 'Memories') 'Save States'
        New-Item -ItemType Directory -Path (Join-Path $script:states 'gb/agg23.GB') -Force | Out-Null
        # Sonic: three states (newest = Sonic #3). Tetris: a single state.
        $mk = {
            param($rel, $daysAgo)
            $p = Join-Path $script:states $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $p) -Force | Out-Null
            "state-$rel" | Set-Content -LiteralPath $p
            (Get-Item -LiteralPath $p).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(-$daysAgo)
        }
        & $mk 'gb/agg23.GB/Sonic.sta'      9
        & $mk 'gb/agg23.GB/Sonic #2.sta'   5
        & $mk 'gb/agg23.GB/Sonic #3.sta'   1
        & $mk 'gb/agg23.GB/Tetris.sta'     3
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    Context 'Get-PocketSaveStateInventory' {
        It 'lists every state grouped by game with the newest flagged' {
            $inv = Get-PocketSaveStateInventory -Root $script:root
            $inv.Total | Should -Be 4
            @($inv.Games).Count | Should -Be 2
            $sonic = @($inv.Games) | Where-Object Game -eq 'Sonic'
            $sonic.Count | Should -Be 3
            # Exactly one latest per game; Sonic's latest is the day-1 file.
            @($inv.Items | Where-Object { $_.Game -eq 'Sonic' -and $_.IsLatestForGame }).Count | Should -Be 1
            ($inv.Items | Where-Object { $_.Game -eq 'Sonic' -and $_.IsLatestForGame }).Name | Should -Be 'Sonic #3.sta'
            # A singleton is its own latest (never auto-deleted).
            ($inv.Items | Where-Object Game -eq 'Tetris').IsLatestForGame | Should -BeTrue
        }
        It 'returns empty for a card with no save states' {
            $bare = Join-Path ([System.IO.Path]::GetTempPath()) ("mc0_" + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $bare -Force | Out-Null
            try { (Get-PocketSaveStateInventory -Root $bare).Total | Should -Be 0 }
            finally { Remove-Item $bare -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    Context 'Remove-PocketSaveState' {
        It 'dry-run reports the selection and deletes nothing' {
            $r = Remove-PocketSaveState -Root $script:root -Paths @('gb/agg23.GB/Sonic.sta', 'gb/agg23.GB/Sonic #2.sta') -DryRun
            $r.DeleteCount | Should -Be 2
            $r.BackupZip | Should -BeNullOrEmpty
            (Get-PocketSaveStateInventory -Root $script:root).Total | Should -Be 4
        }
        It 'deletes exactly the selection and backs it up first (round-trips)' {
            $r = Remove-PocketSaveState -Root $script:root -Paths @('gb/agg23.GB/Sonic.sta', 'gb/agg23.GB/Sonic #2.sta')
            $r.DeleteCount | Should -Be 2
            Test-Path (Join-Path $script:states 'gb/agg23.GB/Sonic.sta') | Should -BeFalse
            Test-Path (Join-Path $script:states 'gb/agg23.GB/Sonic #3.sta') | Should -BeTrue   # newest kept
            Test-Path $r.BackupZip | Should -BeTrue
            # The backup holds both deleted files under "Save States/...".
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($r.BackupZip)
            try { @($zip.Entries.FullName) | Should -Contain 'Save States/gb/agg23.GB/Sonic.sta' }
            finally { $zip.Dispose() }
        }
        It 'refuses paths outside Memories/Save States (traversal/absolute) - reported, not deleted' {
            'secret' | Set-Content (Join-Path $script:root 'outside.txt')
            $r = Remove-PocketSaveState -Root $script:root -Paths @('../../outside.txt', '/etc/hostname', 'gb/agg23.GB/Tetris.sta')
            $r.DeleteCount | Should -Be 1                       # only the legit one
            @($r.Skipped).Count | Should -Be 2
            Test-Path (Join-Path $script:root 'outside.txt') | Should -BeTrue   # untouched
        }
    }

    Context 'Export-PocketSaveStateBackup' {
        It 'zips a selection without deleting; bytes unzip to the originals' {
            $b = Export-PocketSaveStateBackup -Root $script:root -Paths @('gb/agg23.GB/Tetris.sta')
            $b.Count | Should -Be 1
            @($b.Bytes).Count | Should -BeGreaterThan 0
            (Get-PocketSaveStateInventory -Root $script:root).Total | Should -Be 4   # nothing deleted
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + '.zip')
            [System.IO.File]::WriteAllBytes($tmp, $b.Bytes)
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
            try { @($zip.Entries.FullName) | Should -Contain 'Save States/gb/agg23.GB/Tetris.sta' }
            finally { $zip.Dispose(); Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
        }
        It 'backs up ALL states when no paths are given' {
            (Export-PocketSaveStateBackup -Root $script:root).Count | Should -Be 4
        }
    }
}

Describe 'Memory Cleaner API routes' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("mca_" + [System.IO.Path]::GetRandomFileName())
        $states = Join-Path (Join-Path $script:root 'Memories') 'Save States'
        New-Item -ItemType Directory -Path $states -Force | Out-Null
        'a' | Set-Content (Join-Path $states 'Mario.sta')
        'b' | Set-Content (Join-Path $states 'Mario #2.sta')
        $script:state = @{ Root = $script:root; IsTestMode = $true; DryRun = $false }
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'GET /api/savestates returns the inventory' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/savestates' -State $s }
        $r.Status | Should -Be 200
        $r.Body.Total | Should -Be 2
    }
    It 'POST /api/savestates/delete is a dry-run without confirm, deletes with confirm (+ backup)' {
        $body = [pscustomobject]@{ paths = @('Mario.sta') }
        $dry = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body } { param($s, $b)
            Invoke-PocketApiRoute -Method POST -Path '/api/savestates/delete' -Body $b -State $s }
        $dry.Body.DryRun | Should -BeTrue
        $dry.Body.DeleteCount | Should -Be 1
        (Get-PocketSaveStateInventory -Root $script:root).Total | Should -Be 2   # nothing gone yet

        $body2 = [pscustomobject]@{ paths = @('Mario.sta'); confirm = $true }
        $del = InModuleScope PocketPrep -Parameters @{ s = $script:state; b = $body2 } { param($s, $b)
            Invoke-PocketApiRoute -Method POST -Path '/api/savestates/delete' -Body $b -State $s }
        $del.Body.DeleteCount | Should -Be 1
        $del.Body.BackupZip | Should -Not -BeNullOrEmpty
        (Get-PocketSaveStateInventory -Root $script:root).Total | Should -Be 1
    }
    It 'POST /api/savestates/backup returns a base64 zip data URL' {
        $r = InModuleScope PocketPrep -Parameters @{ s = $script:state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/savestates/backup' -Body ([pscustomobject]@{}) -State $s }
        $r.Status | Should -Be 200
        $r.Body.count | Should -Be 2
        $r.Body.dataUrl | Should -Match '^data:application/zip;base64,.+'
    }
}
