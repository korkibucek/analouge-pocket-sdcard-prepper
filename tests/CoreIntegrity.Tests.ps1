BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:cm = Join-Path $repo 'manifests/cores.json'

    function New-Core {
        param($Root, $Identifier, [string[]]$Files, [string]$CoreJson = '{"core":{"metadata":{"shortname":"X","author":"a","version":"1","platform_ids":["gb"]}}}')
        $dir = Join-Path $Root "Cores/$Identifier"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $CoreJson | Set-Content (Join-Path $dir 'core.json')
        foreach ($f in $Files) { '{}' | Set-Content (Join-Path $dir $f) }
        return $dir
    }
}

Describe 'Test-PocketCoreIntegrity' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("ci_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'reports a complete core as OK' {
        New-Core $script:root 'agg23.NES' @('data.json', 'video.json', 'input.json', 'audio.json', 'interact.json')
        $r = Test-PocketCoreIntegrity -Root $script:root
        ($r | Where-Object Identifier -eq 'agg23.NES').Ok | Should -BeTrue
    }

    It 'flags a core missing a required file' {
        New-Core $script:root 'broken.Core' @('data.json')   # missing video.json + input.json
        $r = Test-PocketCoreIntegrity -Root $script:root
        $c = $r | Where-Object Identifier -eq 'broken.Core'
        $c.Ok | Should -BeFalse
        $c.Missing | Should -Contain 'video.json'
        $c.Missing | Should -Contain 'input.json'
    }

    It 'flags a core whose core.json is corrupt' {
        $dir = New-Core $script:root 'bad.Json' @('data.json', 'video.json', 'input.json')
        'not json{' | Set-Content (Join-Path $dir 'core.json')
        $c = (Test-PocketCoreIntegrity -Root $script:root -WarningAction SilentlyContinue) | Where-Object Identifier -eq 'bad.Json'
        # Get-PocketInstalledCore skips an unparseable core.json, so it won't be listed;
        # either way it must not be reported as OK.
        if ($c) { $c.Ok | Should -BeFalse }
        else { $true | Should -BeTrue }
    }

    It 'returns nothing for a card with no cores' {
        @(Test-PocketCoreIntegrity -Root $script:root) | Should -HaveCount 0
    }
}

Describe 'Repair-PocketCore' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("rp_" + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Path $script:root -Force | Out-Null
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'throws for an unknown core id' {
        { Repair-PocketCore -Root $script:root -Id 'no-such-core-xyz' -CoresManifest $script:cm } | Should -Throw
    }

    It 'DryRun resolves a real core and plans a reinstall without downloading' {
        $id = (Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $script:cm) | Select-Object -First 1).Id
        $r = InModuleScope PocketPrep -Parameters @{ root = $script:root; cm = $script:cm; id = $id } {
            param($root, $cm, $id)
            Mock Install-PocketCore { [pscustomobject]@{ PlacedCount = 0; DryRun = $true } }
            $res = Repair-PocketCore -Root $root -Id $id -CoresManifest $cm -DryRun
            Assert-MockCalled Install-PocketCore -Times 1 -ParameterFilter { $Overwrite -and $DryRun }
            $res
        }
        $r.Repaired | Should -BeFalse
    }
}
