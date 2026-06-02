BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    function New-FakeCore($root, $identifier, $version, $platformIds) {
        $dir = Join-Path (Join-Path $root 'Cores') $identifier
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $obj = @{ core = @{ magic = 'APF_VER_1'; metadata = @{
            platform_ids = $platformIds; shortname = $identifier.Split('.')[-1]
            author = $identifier.Split('.')[0]; version = $version; date_release = '2024-01-01' } } }
        ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $dir 'core.json')
    }
}

Describe 'Get-PocketInstalledCore' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_inv_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'returns empty when there is no Cores folder' {
        @(Get-PocketInstalledCore -Root $script:root).Count | Should -Be 0
    }
    It 'reads identifier, version and platform_ids from core.json' {
        New-FakeCore $script:root 'agg23.NES' '1.0.1' @('nes')
        New-FakeCore $script:root 'Spiritualized.GB' '1.3.0' @('gb','gbc')
        $cores = Get-PocketInstalledCore -Root $script:root
        $cores.Count | Should -Be 2
        $nes = $cores | Where-Object Identifier -eq 'agg23.NES'
        $nes.Version | Should -Be '1.0.1'
        $nes.PlatformIds | Should -Contain 'nes'
        ($cores | Where-Object Identifier -eq 'Spiritualized.GB').PlatformIds | Should -Contain 'gbc'
    }
    It 'skips a core folder with no core.json' {
        New-Item -ItemType Directory -Path (Join-Path (Join-Path $script:root 'Cores') 'Broken.Core') -Force | Out-Null
        @(Get-PocketInstalledCore -Root $script:root).Count | Should -Be 0
    }
}

Describe 'Compare-PocketVersion' {
    It 'detects a newer version' {
        (Compare-PocketVersion -Installed '1.0.1' -Latest '1.1.0').UpdateAvailable | Should -BeTrue
    }
    It 'treats equal versions as same (with v prefix)' {
        $c = Compare-PocketVersion -Installed 'v2.3' -Latest '2.3'
        $c.Same | Should -BeTrue
        $c.UpdateAvailable | Should -BeFalse
    }
    It 'handles multi-digit components (1.10 > 1.9)' {
        (Compare-PocketVersion -Installed '1.9.0' -Latest '1.10.0').UpdateAvailable | Should -BeTrue
    }
    It 'reports installed-newer' {
        (Compare-PocketVersion -Installed '2.0' -Latest '1.9').InstalledNewer | Should -BeTrue
    }
    It 'falls back to string compare for non-numeric versions' {
        { Compare-PocketVersion -Installed 'alpha' -Latest 'beta' } | Should -Not -Throw
    }
}

Describe 'Test-PocketPlatformIdInstalled' {
    It 'finds a platform provided by an installed core' {
        $cores = @([pscustomobject]@{ Identifier='agg23.NES'; PlatformIds=@('nes') })
        $r = Test-PocketPlatformIdInstalled -Root '/x' -PlatformId 'nes' -InstalledCore $cores
        $r.Installed | Should -BeTrue
        $r.ProvidedBy | Should -Contain 'agg23.NES'
    }
    It 'returns false when no installed core provides the platform' {
        $cores = @([pscustomobject]@{ Identifier='agg23.NES'; PlatformIds=@('nes') })
        (Test-PocketPlatformIdInstalled -Root '/x' -PlatformId 'snes' -InstalledCore $cores).Installed | Should -BeFalse
    }
}

Describe 'GET /api/installed-cores' {
    It 'returns installed cores via the API' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_apicore_" + [System.IO.Path]::GetRandomFileName())
        New-FakeCore $root 'agg23.NES' '1.0.1' @('nes')
        $state = @{ Root = $root; IsTestMode = $true }
        $r = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method GET -Path '/api/installed-cores' -State $s }
        @($r.Body.cores).Count | Should -Be 1
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
