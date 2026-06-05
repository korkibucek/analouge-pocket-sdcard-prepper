BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:gb = Get-PocketSystem -Path (Join-Path $repo 'manifests/systems.json') -Id 'gb'
}

Describe 'Assert-PocketFreeSpace (pure logic)' {
    It 'passes when required fits in available' {
        InModuleScope PocketPrep {
            { Assert-PocketFreeSpace -Root '/x' -RequiredBytes 100 -AvailableBytes 1000 } | Should -Not -Throw
        }
    }
    It 'throws a clear error when required exceeds available' {
        InModuleScope PocketPrep {
            { Assert-PocketFreeSpace -Root '/x' -RequiredBytes 2000 -AvailableBytes 1000 -Label 'ROMs' } |
                Should -Throw -ExpectedMessage '*Not enough free space*ROMs*'
        }
    }
    It 'is a no-op for zero/negative required and when -Skip' {
        InModuleScope PocketPrep {
            { Assert-PocketFreeSpace -Root '/x' -RequiredBytes 0 -AvailableBytes 1 } | Should -Not -Throw
            { Assert-PocketFreeSpace -Root '/x' -RequiredBytes 9999 -AvailableBytes 1 -Skip } | Should -Not -Throw
        }
    }
}

Describe 'Get-PocketFreeSpace' {
    It 'returns a positive number for the temp folder' {
        InModuleScope PocketPrep {
            (Get-PocketFreeSpace -Path ([System.IO.Path]::GetTempPath())) | Should -BeGreaterThan 0
        }
    }
}

Describe 'Invoke-PocketRomCopyPlan free-space enforcement' {
    BeforeEach {
        $script:src  = Join-Path ([System.IO.Path]::GetTempPath()) ("fs_src_"  + [System.IO.Path]::GetRandomFileName())
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fs_root_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:src, $script:root -Force | Out-Null
        'aaaa' | Set-Content (Join-Path $script:src 'g.gb')
        $script:plan = New-PocketRomCopyPlan -System $script:gb -SourceFolder $script:src -Root $script:root
    }
    AfterEach { Remove-Item $script:src, $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'records the resolved card Root on the plan' {
        $script:plan.Root | Should -Be (Resolve-Path $script:root).Path
    }

    It 'refuses to copy when the destination is (mock) almost full' {
        $plan = $script:plan
        InModuleScope PocketPrep -Parameters @{ plan = $plan } {
            param($plan)
            Mock Get-PocketFreeSpace { 1 }   # 1 byte free
            { Invoke-PocketRomCopyPlan -Plan $plan } | Should -Throw -ExpectedMessage '*Not enough free space*'
        }
        (Test-Path (Join-Path $script:plan.Destination 'g.gb')) | Should -BeFalse
    }

    It 'still copies when -SkipSpaceCheck overrides the (mock) full disk' {
        $plan = $script:plan
        $res = InModuleScope PocketPrep -Parameters @{ plan = $plan } {
            param($plan)
            Mock Get-PocketFreeSpace { 1 }
            Invoke-PocketRomCopyPlan -Plan $plan -SkipSpaceCheck
        }
        $res.CopiedCount | Should -Be 1
    }
}
