BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:sys  = Join-Path $repo 'manifests/systems.json'
    $script:cores = Join-Path $repo 'manifests/cores.json'
}

Describe 'Get-PocketKnownPlatform' {
    It 'includes the built-in systems' {
        $p = Get-PocketKnownPlatform -SystemsManifest $script:sys
        @($p | ForEach-Object { $_.PlatformId }) | Should -Contain 'gb'
        ($p | Where-Object PlatformId -eq 'gb').Source | Should -Be 'system'
    }

    It 'includes catalog-only platforms from the cores manifest' {
        $p = Get-PocketKnownPlatform -SystemsManifest $script:sys -CoresManifest $script:cores
        # 'gameandwatch' is a catalog core (agg23/fpga-gameandwatch) with no built-in system.
        $gw = $p | Where-Object PlatformId -eq 'gameandwatch'
        $gw | Should -Not -BeNullOrEmpty
        $gw.Source | Should -Be 'catalog'
        $gw.SupportedExtensions | Should -Contain '*'
    }

    It 'de-duplicates a platform by id (system wins over catalog)' {
        $p = Get-PocketKnownPlatform -SystemsManifest $script:sys -CoresManifest $script:cores
        @($p | Where-Object PlatformId -eq 'gb').Count | Should -Be 1
        ($p | Where-Object PlatformId -eq 'gb').Source | Should -Be 'system'
    }

    It 'flags arcade catalog platforms and gives romset guidance, not the generic note' {
        $p = Get-PocketKnownPlatform -SystemsManifest $script:sys -CoresManifest $script:cores
        # 'gberet' (Green Beret) is an arcade core in the catalog.
        $gb = $p | Where-Object PlatformId -eq 'gberet'
        $gb | Should -Not -BeNullOrEmpty
        $gb.Arcade | Should -BeTrue
        $gb.Notes | Should -Match 'instance \.json'
        $gb.Notes | Should -Match 'rom-recipes'
        # A non-arcade catalog platform stays unflagged with the generic note.
        $gw = $p | Where-Object PlatformId -eq 'gameandwatch'
        $gw.Arcade | Should -BeFalse
        # Built-in systems are never flagged arcade.
        ($p | Where-Object PlatformId -eq 'gb').Arcade | Should -BeFalse
    }

    It 'includes platforms from installed cores when -Root is given' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("kp_" + [System.IO.Path]::GetRandomFileName())
        $cd = Join-Path $root 'Cores/Some.Mystery'; New-Item -ItemType Directory $cd -Force | Out-Null
        @{ core = @{ metadata = @{ shortname='M'; author='x'; version='1'; platform_ids=@('mystery99') } } } |
            ConvertTo-Json -Depth 6 | Set-Content (Join-Path $cd 'core.json')
        try {
            $p = Get-PocketKnownPlatform -SystemsManifest $script:sys -CoresManifest $script:cores -Root $root
            ($p | Where-Object PlatformId -eq 'mystery99').Source | Should -Be 'installed-core'
        } finally { Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
