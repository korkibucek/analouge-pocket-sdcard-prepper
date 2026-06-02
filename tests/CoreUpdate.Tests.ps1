BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:coresManifest = Join-Path $repo 'manifests/cores.json'
}

Describe 'Update-PocketCore (dry-run, injected status)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_upd_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
        # agg23.NES is in the shipped manifest; the other is not.
        $script:status = @(
            [pscustomobject]@{ Identifier='agg23.NES'; Installed='1.0.0'; Latest='1.0.1'; UpdateAvailable=$true;  InManifest=$true },
            [pscustomobject]@{ Identifier='agg23.SNES'; Installed='1.2.0'; Latest='1.2.0'; UpdateAvailable=$false; InManifest=$true }
        )
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'selects only cores with an available update' {
        $r = Update-PocketCore -Root $script:root -CoresManifest $script:coresManifest -UpdateStatus $script:status -DryRun
        @($r).Count | Should -Be 1
        $r[0].Identifier | Should -Be 'agg23.NES'
        $r[0].Action | Should -Be 'would-update'
        $r[0].To | Should -Be '1.0.1'
    }
    It 'returns nothing when no updates are available' {
        $none = @([pscustomobject]@{ Identifier='agg23.NES'; Installed='1.0.1'; Latest='1.0.1'; UpdateAvailable=$false })
        @(Update-PocketCore -Root $script:root -CoresManifest $script:coresManifest -UpdateStatus $none -DryRun).Count | Should -Be 0
    }
}

Describe 'POST /api/cores/update-all (dry-run)' {
    It 'returns a results array without writing' {
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pp_ua_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $state = @{ Root = $root; IsTestMode = $true; DryRun = $true; CoresManifest = $script:coresManifest }
        $r = InModuleScope PocketPrep -Parameters @{ s = $state } { param($s)
            Invoke-PocketApiRoute -Method POST -Path '/api/cores/update-all' -State $s }
        $r.Status | Should -Be 200
        $r.Body.ContainsKey('results') | Should -BeTrue
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
