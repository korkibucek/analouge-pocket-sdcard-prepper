BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:repo = $repo
}

Describe 'Get-PocketLatestRelease error handling' {
    It 'turns a GitHub 403/rate-limit into a clear, actionable message' {
        InModuleScope PocketPrep {
            Mock Invoke-PocketRest { throw 'Response status code does not indicate success: 403 (rate limit exceeded).' }
            { Get-PocketLatestRelease -Owner 'a' -Repo 'b' } | Should -Throw -ExpectedMessage '*rate limit*GITHUB_TOKEN*'
        }
    }
    It 'reports a 404 release clearly' {
        InModuleScope PocketPrep {
            Mock Invoke-PocketRest { throw 'Response status code does not indicate success: 404 (Not Found).' }
            { Get-PocketLatestRelease -Owner 'a' -Repo 'b' -Tag 'v9' } | Should -Throw -ExpectedMessage "*not found*"
        }
    }
    It 'reports a generic offline/network error clearly' {
        InModuleScope PocketPrep {
            Mock Invoke-PocketRest { throw 'No such host is known.' }
            { Get-PocketLatestRelease -Owner 'a' -Repo 'b' } | Should -Throw -ExpectedMessage '*Could not reach GitHub*'
        }
    }
}

Describe 'Install-PocketCore download failure handling' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("ep_core_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        $script:core = [pscustomobject]@{ Id='nes'; Identifier='agg23.NES'; Owner='agg23'; Repo='openfpga-NES'; PlatformIds=@('nes') }
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'surfaces a release-resolution failure and writes nothing' {
        $root = $script:root; $core = $script:core
        InModuleScope PocketPrep -Parameters @{ root = $root; core = $core } {
            param($root, $core)
            Mock Get-PocketLatestRelease { throw 'GitHub API rate limit reached. Set GITHUB_TOKEN ...' }
            { Install-PocketCore -Root $root -Core $core -Download } | Should -Throw -ExpectedMessage '*rate limit*'
        }
        (Test-Path (Join-Path $script:root 'Cores')) | Should -BeFalse
    }

    It 'surfaces a download failure and writes nothing' {
        $root = $script:root; $core = $script:core
        InModuleScope PocketPrep -Parameters @{ root = $root; core = $core } {
            param($root, $core)
            Mock Get-PocketLatestRelease { [pscustomobject]@{ Version='1.0.1'; ZipUrl='https://github.com/x/y/releases/download/1.0.1/c.zip'; ZipName='c.zip' } }
            Mock Invoke-PocketDownload { throw 'Failed download https://...: The operation has timed out.' }
            { Install-PocketCore -Root $root -Core $core -Download } | Should -Throw -ExpectedMessage '*timed out*'
        }
        (Test-Path (Join-Path $script:root 'Cores')) | Should -BeFalse
    }
}

Describe 'Install-PocketFirmware download failure handling' {
    It 'surfaces a download failure and leaves no firmware on the card' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("ep_fw_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $rel = [pscustomobject]@{ version='2.5'; fileName='pocket_firmware_2_5.bin'; md5=('a'*32); sizeBytes=100; url='https://www.analogue.co/x/download' }
        InModuleScope PocketPrep -Parameters @{ root = $root; rel = $rel } {
            param($root, $rel)
            Mock Invoke-PocketDownload { throw 'Failed download: connection reset by peer.' }
            { Install-PocketFirmware -Root $root -Release $rel } | Should -Throw -ExpectedMessage '*connection reset*'
        }
        (Get-ChildItem $root -Filter *.bin -ErrorAction SilentlyContinue).Count | Should -Be 0
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-PocketRomCopyPlan IO failure handling' {
    It 'records a permission-denied copy as failed (does not throw or report success)' {
        $repo = $script:repo
        $src  = Join-Path ([System.IO.Path]::GetTempPath()) ("ep_src_"  + [System.IO.Path]::GetRandomFileName())
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("ep_root_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $src, $root -Force | Out-Null
        'a' | Set-Content (Join-Path $src 'g1.gb'); 'b' | Set-Content (Join-Path $src 'g2.gb')
        $gb = Get-PocketSystem -Path (Join-Path $repo 'manifests/systems.json') -Id 'gb'
        $plan = New-PocketRomCopyPlan -System $gb -SourceFolder $src -Root $root
        $res = InModuleScope PocketPrep -Parameters @{ plan = $plan } {
            param($plan)
            Mock Copy-Item { throw 'Access to the path is denied.' }
            Invoke-PocketRomCopyPlan -Plan $plan
        }
        $res.FailedCount | Should -Be 2
        $res.CopiedCount | Should -Be 0
        Remove-Item $src, $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
