BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:cm = Join-Path $repo 'manifests/cores.json'
    $script:subset = @('agg23-nes', 'agg23-snes', 'agg23-pc-engine')
}

Describe 'Install-PocketCoreSet' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("cs_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'DryRun lists would-install for a subset and does not download' {
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; ids = $script:subset } {
            param($root, $cm, $ids)
            Mock Install-PocketCore { throw 'must not download in dry-run' }
            $res = Install-PocketCoreSet -Root $root -CoresManifest $cm -Id $ids -DryRun
            Assert-MockCalled Install-PocketCore -Times 0
            $res
        }
        $r.Requested | Should -Be 3
        @($r.Results | Where-Object Status -eq 'would-install').Count | Should -Be 3
    }

    It 'installs each requested core and aggregates results' {
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; ids = $script:subset } {
            param($root, $cm, $ids)
            Mock Install-PocketCore { [pscustomobject]@{ PlacedCount = 12; Version = '1.0' } }
            Install-PocketCoreSet -Root $root -CoresManifest $cm -Id $ids
        }
        $r.InstalledCount | Should -Be 3
        $r.FailedCount | Should -Be 0
    }

    It 'continues past a failing core' {
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; ids = $script:subset } {
            param($root, $cm, $ids)
            Mock Install-PocketCore { if ($Core.Identifier -eq 'agg23.NES') { throw 'boom' } else { [pscustomobject]@{ PlacedCount = 5; Version = '1' } } }
            Install-PocketCoreSet -Root $root -CoresManifest $cm -Id $ids
        }
        $r.FailedCount | Should -Be 1
        $r.InstalledCount | Should -Be 2
    }

    It 'stops early when GitHub rate-limits and marks the rest skipped' {
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; ids = $script:subset } {
            param($root, $cm, $ids)
            Mock Install-PocketCore { throw 'GitHub API rate limit reached. Set GITHUB_TOKEN ...' }
            Install-PocketCoreSet -Root $root -CoresManifest $cm -Id $ids
        }
        $r.RateLimited | Should -BeTrue
        $r.FailedCount | Should -Be 1               # the first one
        @($r.Results | Where-Object Status -eq 'skipped').Count | Should -Be 2
    }
}

Describe 'POST /api/cores/install-all (dry-run)' {
    It 'returns an aggregate result' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("cs_api_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $state = @{ Root = $root; IsTestMode = $true; DryRun = $true; CoresManifest = $script:cm }
        $body = [pscustomobject]@{ ids = $script:subset }
        $r = InModuleScope PocketPrep -Parameters @{ s = $state; b = $body } { param($s, $b)
            Invoke-PocketApiRoute -Method POST -Path '/api/cores/install-all' -Body $b -State $s }
        $r.Status | Should -Be 200
        $r.Body.Requested | Should -Be 3
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
