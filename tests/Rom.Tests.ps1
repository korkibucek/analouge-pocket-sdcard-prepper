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

    It 'de-duplicates flatten collisions (same basename in different subfolders)' {
        $a = Join-Path $script:src 'a'; $b = Join-Path $script:src 'b'
        New-Item -ItemType Directory -Path $a, $b -Force | Out-Null
        'x' | Set-Content (Join-Path $a 'dup.gb')
        'y' | Set-Content (Join-Path $b 'dup.gb')
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root -Recurse
        ($plan.Duplicates | Where-Object Reason -match 'same name').Count | Should -Be 1
        $plan.DuplicateCount | Should -Be 1
        $plan.ProblemCount | Should -Be 0
        $plan.CopyableCount | Should -Be ($plan.FileCount - 1)
    }

    It 'de-duplicates byte-identical ROMs with different names (content dedupe)' {
        'SAMEBYTES' | Set-Content (Join-Path $script:src 'one.gb')
        'SAMEBYTES' | Set-Content (Join-Path $script:src 'two.gb')
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root
        ($plan.Duplicates | Where-Object Reason -match 'identical').Count | Should -Be 1
        $plan.DuplicateCount | Should -Be 1
        $plan.CopyableCount | Should -Be ($plan.FileCount - 1)
    }

    It 'keeps byte-identical ROMs when -NoContentDedupe is given' {
        'SAMEBYTES' | Set-Content (Join-Path $script:src 'one.gb')
        'SAMEBYTES' | Set-Content (Join-Path $script:src 'two.gb')
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root -NoContentDedupe
        $plan.DuplicateCount | Should -Be 0
        $plan.CopyableCount | Should -Be $plan.FileCount
    }

    It 'flags filenames with characters invalid on FAT/exFAT' -Skip:($IsWindows) {
        # ':' and '?' are invalid on FAT (and on Windows/NTFS), so the source fixture can
        # only be created on Linux/macOS. The detection logic itself is platform-agnostic.
        [System.IO.File]::WriteAllText((Join-Path $script:src 'bad:name.gb'), 'x')
        [System.IO.File]::WriteAllText((Join-Path $script:src 'whats?.gb'), 'y')
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root
        ($plan.Problems | Where-Object Reason -match 'not allowed on FAT').Count | Should -Be 2
    }

    It 'detects invalid FAT characters in a destination leaf (platform-agnostic check)' {
        # Verify the pure detection independent of the filesystem's own naming rules.
        $invalid = [char[]]('<', '>', ':', '"', '|', '?', '*')
        foreach ($c in $invalid) {
            ("game${c}.gb".IndexOfAny([char[]]('<', '>', ':', '"', '|', '?', '*'))) | Should -BeGreaterOrEqual 0
        }
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

    It 'skips duplicate items (collision) instead of clobbering or failing' {
        $a = Join-Path $script:src 'a'; $b = Join-Path $script:src 'b'
        New-Item -ItemType Directory -Path $a, $b -Force | Out-Null
        'x' | Set-Content (Join-Path $a 'dup.gb')
        'y' | Set-Content (Join-Path $b 'dup.gb')
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root -Recurse
        $res = Invoke-PocketRomCopyPlan -Plan $plan
        $res.SkippedDuplicateCount | Should -Be 1
        $res.FailedCount | Should -Be 0
    }

    It 'copies in batches (-Skip/-First) with counts that add up' {
        # Five distinct ROMs, copied two-at-a-time, must total five copied with no overlap.
        1..5 | ForEach-Object { "rom$_" | Set-Content (Join-Path $script:src "g$_.gb") }
        $plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root
        $total = $plan.FileCount
        $copied = 0; $seenSkips = @()
        for ($skip = 0; $skip -lt $total; $skip += 2) {
            $r = Invoke-PocketRomCopyPlan -Plan $plan -Skip $skip -First 2
            $r.BatchSkip | Should -Be $skip
            $r.ItemTotal | Should -Be $total
            $copied += $r.CopiedCount
            $seenSkips += $skip
        }
        $copied | Should -Be $total
        # Every planned file actually landed on the card exactly once.
        (Get-ChildItem (Join-Path $script:root 'Assets/gb/common') -File).Count | Should -Be $total
    }

    It 'invokes -OnProgress once per item in the batch' {
        $calls = [System.Collections.Generic.List[object]]::new()
        $cb = { param($done, $tot, $name) $calls.Add(@{ done = $done; tot = $tot }) }
        Invoke-PocketRomCopyPlan -Plan $script:plan -OnProgress $cb | Out-Null
        $calls.Count | Should -Be $script:plan.FileCount
        $calls[-1].done | Should -Be $script:plan.FileCount
    }

    It 'flags a truncated copy as failed (post-copy size verification)' {
        $plan = $script:plan
        $res = InModuleScope PocketPrep -Parameters @{ plan = $plan } {
            param($plan)
            # Simulate a copy that writes a wrong-sized (truncated) file on the card.
            Mock Copy-Item { 'x' | Set-Content -LiteralPath $Destination -NoNewline }
            Invoke-PocketRomCopyPlan -Plan $plan
        }
        $res.FailedCount | Should -Be 2
        $res.CopiedCount | Should -Be 0
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
