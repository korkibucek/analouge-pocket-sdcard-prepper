BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    $script:manifest = [pscustomobject]@{
        latest = '2.5'
        releases = @(
            [pscustomobject]@{ version = '2.4'; releaseDate = '2024-09-01' },
            [pscustomobject]@{ version = '2.5'; releaseDate = '2025-03-18' }
        )
    }
}

Describe 'Test-PocketFirmwareManifestAge' {
    It 'reports not-stale when the newest release is recent' {
        $r = Test-PocketFirmwareManifestAge -Manifest $script:manifest -AsOfDate ([datetime]'2025-04-01') -WarnAfterDays 270
        $r.Stale | Should -BeFalse
        $r.NewestReleaseDate | Should -Be '2025-03-18'
    }
    It 'reports stale when the newest release is older than the threshold' {
        $r = Test-PocketFirmwareManifestAge -Manifest $script:manifest -AsOfDate ([datetime]'2026-06-01') -WarnAfterDays 270
        $r.Stale | Should -BeTrue
        $r.AgeDays | Should -BeGreaterThan 270
    }
    It 'uses the NEWEST release date, not the first' {
        (Test-PocketFirmwareManifestAge -Manifest $script:manifest -AsOfDate ([datetime]'2025-04-01')).NewestReleaseDate | Should -Be '2025-03-18'
    }
    It 'handles a manifest with an unparseable date gracefully' {
        $bad = [pscustomobject]@{ latest='x'; releases=@([pscustomobject]@{ version='x'; releaseDate='not-a-date' }) }
        $r = Test-PocketFirmwareManifestAge -Manifest $bad
        $r.NewestReleaseDate | Should -BeNullOrEmpty
        $r.Stale | Should -BeFalse
    }
    It 'validates against the shipped manifest without throwing' {
        $m = Get-PocketFirmwareManifest -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'manifests/firmware.json')
        { Test-PocketFirmwareManifestAge -Manifest $m } | Should -Not -Throw
    }
}
