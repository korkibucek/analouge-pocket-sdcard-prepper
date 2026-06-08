BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:systemsManifest = Join-Path $repo 'manifests/systems.json'

    function New-FakeCore {
        param($Root, $Identifier, $PlatformIds)
        $dir = Join-Path $Root "Cores/$Identifier"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        @{ core = @{ metadata = @{ shortname = $Identifier; author = 'x'; version = '1.0'; platform_ids = @($PlatformIds) } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $dir 'core.json')
    }
}

Describe 'Get-PocketImportablePlatform' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("imp_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'returns platforms from installed cores that the manifest does not cover' {
        New-FakeCore $script:root 'Some.WonderSwan' 'wonderswan'
        New-FakeCore $script:root 'agg23.NES' 'nes'         # already covered by the manifest
        $p = Get-PocketImportablePlatform -Root $script:root -SystemsManifest $script:systemsManifest
        @($p.PlatformId) | Should -Contain 'wonderswan'
        @($p.PlatformId) | Should -Not -Contain 'nes'      # manifest already covers it
        ($p | Where-Object PlatformId -eq 'wonderswan').SupportedExtensions | Should -Contain '*'
    }

    It 'de-duplicates a platform provided by more than one core' {
        New-FakeCore $script:root 'A.Foo' 'foo'
        New-FakeCore $script:root 'B.Foo' 'foo'
        $p = @(Get-PocketImportablePlatform -Root $script:root -SystemsManifest $script:systemsManifest)
        @($p | Where-Object PlatformId -eq 'foo').Count | Should -Be 1
    }

    It 'returns nothing for a card with no cores' {
        @(Get-PocketImportablePlatform -Root $script:root -SystemsManifest $script:systemsManifest).Count | Should -Be 0
    }
}

Describe 'New-PocketRomCopyPlan match-all (*) for generic platforms' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("impr_" + [System.IO.Path]::GetRandomFileName())
        $script:src  = Join-Path ([System.IO.Path]::GetTempPath()) ("imps_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root, $script:src -Force | Out-Null
        'a' | Set-Content (Join-Path $script:src 'game.ws')
        'b' | Set-Content (Join-Path $script:src 'game.bin')
    }
    AfterEach { Remove-Item $script:root, $script:src -Recurse -Force -ErrorAction SilentlyContinue }

    It "copies any file when SupportedExtensions is '*'" {
        $sys = [pscustomobject]@{ Id='wonderswan'; PlatformId='wonderswan'; SupportedExtensions=@('*') }
        $plan = New-PocketRomCopyPlan -System $sys -SourceFolder $script:src -Root $script:root
        $plan.FileCount | Should -Be 2
        $plan.SkippedNonMatching | Should -Be 0
        $plan.Destination | Should -Match 'Assets.*wonderswan.*common'
    }
}
