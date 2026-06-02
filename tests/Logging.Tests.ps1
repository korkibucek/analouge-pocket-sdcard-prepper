BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'Logging' {
    BeforeEach {
        $script:logPath = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_log_" + [System.IO.Path]::GetRandomFileName() + '.log')
    }
    AfterEach { Remove-Item $script:logPath -Force -ErrorAction SilentlyContinue }

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
