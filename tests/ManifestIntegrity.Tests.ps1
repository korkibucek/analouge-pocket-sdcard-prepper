BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:m = Join-Path $repo 'manifests'
}

Describe 'Shipped manifests are valid and consistent' {
    It 'firmware.json: latest resolves and every release has a 32-hex md5' {
        $fw = Get-PocketFirmwareManifest -Path (Join-Path $script:m 'firmware.json')
        (Resolve-PocketFirmwareRelease -Manifest $fw).version | Should -Be $fw.latest
        foreach ($r in $fw.releases) { $r.md5 | Should -Match '^[0-9a-fA-F]{32}$' }
    }
    It 'systems.json: ids are unique and every system has a platformId' {
        $systems = Get-PocketSystem -Path (Join-Path $script:m 'systems.json')
        ($systems.Id | Sort-Object -Unique).Count | Should -Be @($systems).Count
        foreach ($s in $systems) { $s.PlatformId | Should -Not -BeNullOrEmpty }
    }
    It 'systems.json: Neo Geo Pocket uses the jtngp platform-id (jotego core), not ngpc (#229)' {
        # The real community core is jotego.jtngp -> Assets/jtngp/common. A stale 'ngpc'
        # platformId pointed users at the wrong folder (found via the robs-pocket-sdcard report).
        $ngp = Get-PocketSystem -Path (Join-Path $script:m 'systems.json') -Id ngpc
        $ngp.PlatformId | Should -Be 'jtngp'
    }
    It 'cores.json: identifiers look like Author.CoreName with owner/repo' {
        $cores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path (Join-Path $script:m 'cores.json'))
        foreach ($c in $cores) {
            $c.Identifier | Should -Match '^[^.]+\.'
            $c.Owner | Should -Not -BeNullOrEmpty
            $c.Repo  | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Validate-Manifests.ps1' {
    It 'passes on the shipped manifests (exit 0)' {
        pwsh -NoProfile -File (Join-Path $script:m '../scripts/Validate-Manifests.ps1') *> $null
        $LASTEXITCODE | Should -Be 0
    }
    It 'fails on a broken manifest directory (exit 1)' {
        $bad = Join-Path ([System.IO.Path]::GetTempPath()) ("mf_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $bad -Force | Out-Null
        '{ "latest":"9.9","releases":[] }' | Set-Content (Join-Path $bad 'firmware.json')
        '{ "systems":[] }'                  | Set-Content (Join-Path $bad 'systems.json')
        pwsh -NoProfile -File (Join-Path $script:m '../scripts/Validate-Manifests.ps1') -ManifestDirectory $bad *> $null
        $LASTEXITCODE | Should -Be 1
        Remove-Item $bad -Recurse -Force -ErrorAction SilentlyContinue
    }
}
