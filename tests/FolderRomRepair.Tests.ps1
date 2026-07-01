BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
    $script:repo = $repo
    $script:sm = Join-Path $repo 'manifests/systems.json'
}

Describe 'Neo Geo fix-up (folder-ROM repair) engine (#221)' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("fx_" + [System.IO.Path]::GetRandomFileName())
        $core = Join-Path $script:root 'Assets/ng/Mazamars312.NeoGeo'
        New-Item -ItemType Directory -Path $core -Force | Out-Null
        # Two known games; each instance lists srom/prom/crom0.
        '{"instance":{"data_path":"mslug4","data_slots":[{"id":3,"filename":"srom"},{"id":4,"filename":"prom"},{"id":5,"filename":"crom0"}]}}' |
            Set-Content (Join-Path $core 'Metal Slug 4.json')
        '{"instance":{"data_path":"kof98","data_slots":[{"id":3,"filename":"srom"},{"id":4,"filename":"prom"}]}}' |
            Set-Content (Join-Path $core "King of Fighters 98.json")
        $script:common = Join-Path $script:root 'Assets/ng/common'
        New-Item -ItemType Directory -Path $script:common -Force | Out-Null
        $script:mkgame = {
            param($folder, [string[]]$files)
            $d = Join-Path $script:common $folder
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            foreach ($f in $files) { 'x' | Set-Content (Join-Path $d $f) }
        }
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'marks a correctly named, complete folder OK' {
        & $script:mkgame 'mslug4' @('srom', 'prom', 'crom0')
        $p = Get-PocketFolderRomRepairPlan -Root $script:root -PlatformId ng -SystemsManifest $script:sm
        $p.CoreInstalled | Should -BeTrue
        $p.OkCount | Should -Be 1
        $p.RenameCount | Should -Be 0
        $p.AttentionCount | Should -Be 0
    }

    It 'proposes a rename when a folder maps to a game by title (Metal Slug 4 -> mslug4)' {
        & $script:mkgame 'Metal Slug 4' @('srom', 'prom', 'crom0')
        $p = Get-PocketFolderRomRepairPlan -Root $script:root -PlatformId ng -SystemsManifest $script:sm
        $p.RenameCount | Should -Be 1
        $p.Renames[0].From | Should -Be 'Metal Slug 4'
        $p.Renames[0].To | Should -Be 'mslug4'
    }

    It 'flags a correctly named folder that is missing slot files' {
        & $script:mkgame 'mslug4' @('prom')   # srom + crom0 missing
        $p = Get-PocketFolderRomRepairPlan -Root $script:root -PlatformId ng -SystemsManifest $script:sm
        $p.AttentionCount | Should -Be 1
        $p.Attention[0].Kind | Should -Be 'missing'
        $p.Attention[0].Detail | Should -Match 'srom'
    }

    It 'flags a MAME-looking folder (contains a .zip) and an unknown folder' {
        & $script:mkgame 'somegame' @('somegame.zip')   # unknown + zip
        $p = Get-PocketFolderRomRepairPlan -Root $script:root -PlatformId ng -SystemsManifest $script:sm
        $a = $p.Attention[0]
        $a.Kind | Should -Be 'unknown'
        $a.Detail | Should -Match 'MAME|DarkSoft'
    }

    It 'reports a conflict rather than clobbering when the rename target exists' {
        & $script:mkgame 'mslug4' @('srom', 'prom', 'crom0')       # target already there
        & $script:mkgame 'Metal Slug 4' @('srom', 'prom', 'crom0') # would rename onto it
        $p = Get-PocketFolderRomRepairPlan -Root $script:root -PlatformId ng -SystemsManifest $script:sm
        $p.RenameCount | Should -Be 0
        ($p.Attention | Where-Object Kind -eq 'conflict').Count | Should -Be 1
    }

    It 'CoreInstalled is false when no instance jsons exist' {
        Remove-Item (Join-Path $script:root 'Assets/ng/Mazamars312.NeoGeo') -Recurse -Force
        & $script:mkgame 'mslug4' @('srom')
        (Get-PocketFolderRomRepairPlan -Root $script:root -PlatformId ng -SystemsManifest $script:sm).CoreInstalled | Should -BeFalse
    }

    Context 'Invoke-PocketFolderRomRepair' {
        It 'dry-run reports the rename but changes nothing' {
            & $script:mkgame 'Metal Slug 4' @('srom', 'prom', 'crom0')
            $r = Invoke-PocketFolderRomRepair -Root $script:root -PlatformId ng -SystemsManifest $script:sm -DryRun
            $r.DryRun | Should -BeTrue
            $r.RenamedCount | Should -Be 1
            Test-Path (Join-Path $script:common 'Metal Slug 4') | Should -BeTrue
            Test-Path (Join-Path $script:common 'mslug4') | Should -BeFalse
        }
        It 'applies the rename so the folder matches the core data_path' {
            & $script:mkgame 'Metal Slug 4' @('srom', 'prom', 'crom0')
            $r = Invoke-PocketFolderRomRepair -Root $script:root -PlatformId ng -SystemsManifest $script:sm
            $r.RenamedCount | Should -Be 1
            Test-Path (Join-Path $script:common 'mslug4/srom') | Should -BeTrue
            Test-Path (Join-Path $script:common 'Metal Slug 4') | Should -BeFalse
            # The renamed game is now recognised as installed.
            (@(Get-PocketInstanceGame -Root $script:root -PlatformId ng) | Where-Object DataPath -eq 'mslug4').Installed | Should -BeTrue
        }
        It 'never touches folders needing attention (missing data left in place)' {
            & $script:mkgame 'mslug4' @('prom')   # missing srom/crom0
            $r = Invoke-PocketFolderRomRepair -Root $script:root -PlatformId ng -SystemsManifest $script:sm
            $r.RenamedCount | Should -Be 0
            $r.AttentionCount | Should -Be 1
            Test-Path (Join-Path $script:common 'mslug4/prom') | Should -BeTrue
        }
    }

    Context 'API routes' {
        It 'POST /api/folderrom/repair-plan returns the plan; repair is confirm-gated' {
            & $script:mkgame 'Metal Slug 4' @('srom', 'prom', 'crom0')
            $state = @{ Root = $script:root; IsTestMode = $true; DryRun = $false; SystemsManifest = $script:sm }
            $body = [pscustomobject]@{ platformId = 'ng' }
            $plan = InModuleScope PocketPrep -Parameters @{ s = $state; b = $body } { param($s, $b)
                Invoke-PocketApiRoute -Method POST -Path '/api/folderrom/repair-plan' -Body $b -State $s }
            $plan.Status | Should -Be 200
            $plan.Body.RenameCount | Should -Be 1

            # No confirm -> dry-run, folder unchanged.
            $dry = InModuleScope PocketPrep -Parameters @{ s = $state; b = $body } { param($s, $b)
                Invoke-PocketApiRoute -Method POST -Path '/api/folderrom/repair' -Body $b -State $s }
            $dry.Body.DryRun | Should -BeTrue
            Test-Path (Join-Path $script:common 'mslug4') | Should -BeFalse

            # Confirm -> applied.
            $body2 = [pscustomobject]@{ platformId = 'ng'; confirm = $true }
            $go = InModuleScope PocketPrep -Parameters @{ s = $state; b = $body2 } { param($s, $b)
                Invoke-PocketApiRoute -Method POST -Path '/api/folderrom/repair' -Body $b -State $s }
            $go.Body.RenamedCount | Should -Be 1
            Test-Path (Join-Path $script:common 'mslug4/srom') | Should -BeTrue
        }
    }
}
