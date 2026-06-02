BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:repo = $repo
}

Describe 'End-to-end against a fake SD root (test mode)' {
    BeforeAll {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_e2e_" + [System.IO.Path]::GetRandomFileName())
        $script:src  = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_e2esrc_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:src -Force | Out-Null
        'rom' | Set-Content (Join-Path $script:src 'mario.nes')
        'rom' | Set-Content (Join-Path $script:src 'zelda.nes')

        # firmware payload to install offline
        $script:fw = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_e2efw_" + [System.IO.Path]::GetRandomFileName() + '.bin')
        'fw' | Set-Content -LiteralPath $script:fw -NoNewline
        $script:fwMd5 = (Get-FileHash $script:fw -Algorithm MD5).Hash.ToLowerInvariant()
    }
    AfterAll {
        Remove-Item $script:root,$script:src,$script:fw -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'runs the full workflow without touching removable storage' {
        $target = New-PocketTarget -Root $script:root -TestMode
        $target.IsTestMode | Should -BeTrue

        (Test-PocketCardEmpty -Root $target.Root).IsEmpty | Should -BeTrue

        $fwResult = Install-PocketFirmware -Root $target.Root -LocalFile $script:fw -ExpectedMd5 $script:fwMd5
        $fwResult.Md5Verified | Should -BeTrue

        $folderResult = New-PocketFolderStructure -Root $target.Root
        (Test-Path (Join-Path $target.Root 'Assets')) | Should -BeTrue

        $nes  = Get-PocketSystem -Path (Join-Path $script:repo 'manifests/systems.json') -Id 'nes'
        $plan = New-PocketRomCopyPlan -System $nes -SourceFolder $script:src -Root $target.Root
        $romResult = Invoke-PocketRomCopyPlan -Plan $plan
        $romResult.CopiedCount | Should -Be 2
        (Test-Path (Join-Path $target.Root 'Assets/nes/common/mario.nes')) | Should -BeTrue

        $summary = New-PocketInstallSummary -Target $target -FirmwareResult $fwResult -FolderResult $folderResult -RomResults @($romResult)
        $summary.TotalRomsCopied | Should -Be 2
    }
}
