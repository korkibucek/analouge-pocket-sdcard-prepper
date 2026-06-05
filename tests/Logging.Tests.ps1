BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Logging' {
    BeforeEach {
        $script:logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_log_" + [System.IO.Path]::GetRandomFileName() + '.log')
    }
    AfterEach { Remove-Item $script:logPath -Force -ErrorAction SilentlyContinue }

    It 'prunes old logs beyond the retention limit' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_logret_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        # Create 6 existing logs with increasing timestamps.
        1..6 | ForEach-Object {
            $f = Join-Path $dir ("pocketprep-2026010{0}-000000.log" -f $_)
            "old$_" | Set-Content -LiteralPath $f
            (Get-Item $f).LastWriteTime = (Get-Date).AddMinutes(-100 + $_)
        }
        # New logger with MaxKeep=3 should leave 3 total (2 newest existing + the new one's slot).
        $null = New-PocketLogger -Path (Join-Path $dir 'pocketprep-20260108-000000.log') -MaxKeep 3
        (Get-ChildItem $dir -Filter 'pocketprep-*.log').Count | Should -BeLessOrEqual 3
        # The two newest existing logs (5,6) should survive.
        (Test-Path (Join-Path $dir 'pocketprep-20260106-000000.log')) | Should -BeTrue
        (Test-Path (Join-Path $dir 'pocketprep-20260101-000000.log')) | Should -BeFalse
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'does not prune when MaxKeep is 0' {
        $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_logret0_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        1..4 | ForEach-Object { "x" | Set-Content (Join-Path $dir ("pocketprep-2026020{0}-000000.log" -f $_)) }
        $null = New-PocketLogger -Path (Join-Path $dir 'pocketprep-new.log') -MaxKeep 0
        (Get-ChildItem $dir -Filter 'pocketprep-*.log').Count | Should -Be 4
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'writes timestamped entries to memory and file' {
        $logger = New-PocketLogger -Path $script:logPath
        Write-PocketLog -Logger $logger -Message 'hello' | Out-Null
        Write-PocketLog -Logger $logger -Message 'oops' -Level ERROR | Out-Null
        $logger.Entries.Count | Should -Be 2
        $logger.Entries[1] | Should -Match '\[ERROR\] oops'
        (Get-Content $script:logPath).Count | Should -Be 2
    }
}

Describe 'New-PocketInstallSummary' {
    It 'summarises firmware, folders, and ROM counts' {
        $target = [pscustomobject]@{ Root='/tmp/fake'; IsTestMode=$true }
        $fw  = [pscustomobject]@{ Version='2.5'; FileName='pocket_firmware_2_5.bin'; Md5Verified=$true; DryRun=$false }
        $fld = [pscustomobject]@{ Created=@('Assets','Cores'); Existing=@() }
        $rom = @([pscustomobject]@{ SystemId='gb'; CopiedCount=3; SkippedCount=0; FailedCount=0; DryRun=$false })
        $s = New-PocketInstallSummary -Target $target -FirmwareResult $fw -FolderResult $fld -RomResults $rom
        $s.TotalRomsCopied | Should -Be 3
        $s.Text | Should -Match 'Firmware: v2.5'
        $s.Text | Should -Match 'gb: 3 copied'
        "$s" | Should -Match 'TEST MODE'
    }
}
