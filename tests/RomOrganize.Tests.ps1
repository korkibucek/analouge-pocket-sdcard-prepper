BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    function New-Roms {
        param($Common, [string[]]$Names)
        New-Item -ItemType Directory -Path $Common -Force | Out-Null
        foreach ($n in $Names) { "rom-$n" | Set-Content (Join-Path $Common $n) }
    }
}

Describe 'New-PocketRomOrganizePlan' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("org_" + [System.IO.Path]::GetRandomFileName())
        $script:common = Join-Path $script:root 'Assets/gb/common'
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'leaves a small library at the common root (no buckets)' {
        New-Roms $script:common @('a.gb', 'b.gb', 'c.gb')
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 1000
        $plan.NeedsBuckets | Should -BeFalse
        $plan.MoveCount | Should -Be 0
        ($plan.Items | Where-Object Action -ne 'None').Count | Should -Be 0
    }

    It 'splits a large library into capped subfolders' {
        $names = 1..10 | ForEach-Object { '{0:D3}.gb' -f $_ }   # 001..010
        New-Roms $script:common $names
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 4
        $plan.NeedsBuckets | Should -BeTrue
        $plan.BucketCount | Should -Be 3                       # 4 + 4 + 2
        # No bucket holds more than the cap.
        ($plan.Items | Group-Object Bucket | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum | Should -BeLessOrEqual 4
        ($plan.Items | Where-Object Action -eq 'Move').Count | Should -Be 10
    }

    It 'buckets letters into ranges and keeps each under the cap' {
        New-Roms $script:common @('Aaa.gb','Bbb.gb','Ccc.gb','Ddd.gb','Eee.gb')
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 2
        $plan.Buckets.Count | Should -Be 3
        $plan.Buckets[0] | Should -Match '^[A-Z](-[A-Z])?$'    # e.g. "A-B"
    }

    It 'excludes BIOS files from being moved' {
        $names = 1..6 | ForEach-Object { "g$_.gb" }
        New-Roms $script:common $names
        'bios' | Set-Content (Join-Path $script:common 'neogeo.zip')
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 3 -ExcludeFiles @('neogeo.zip')
        $plan.ExcludedCount | Should -Be 1
        ($plan.Items | Where-Object { $_.Source -match 'neogeo' }).Count | Should -Be 0
    }

    It 'throws for a platform with no ROM folder' {
        { New-PocketRomOrganizePlan -Root $script:root -PlatformId 'nope' } | Should -Throw
    }
}

Describe 'Invoke-PocketRomOrganizePlan' {
    BeforeEach {
        $script:root = Join-Path ([System.IO.Path]::GetTempPath()) ("orgx_" + [System.IO.Path]::GetRandomFileName())
        $script:common = Join-Path $script:root 'Assets/gb/common'
        New-Roms $script:common (1..10 | ForEach-Object { '{0:D3}.gb' -f $_ })
    }
    AfterEach { Remove-Item $script:root -Recurse -Force -ErrorAction SilentlyContinue }

    It 'moves files into subfolders, nothing lost' {
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 4
        $res = Invoke-PocketRomOrganizePlan -Plan $plan
        $res.MovedCount | Should -Be 10
        $res.FailedCount | Should -Be 0
        # All 10 files still exist somewhere under common, none at the root anymore.
        @(Get-ChildItem -LiteralPath $script:common -File -Recurse).Count | Should -Be 10
        @(Get-ChildItem -LiteralPath $script:common -File).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $script:common -Directory).Count | Should -Be 3
    }

    It 'is idempotent: re-organizing an organized library moves nothing' {
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 4
        Invoke-PocketRomOrganizePlan -Plan $plan | Out-Null
        $plan2 = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 4
        $plan2.MoveCount | Should -Be 0
    }

    It 'can flatten back to the root when the cap is raised' {
        Invoke-PocketRomOrganizePlan -Plan (New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 4) | Out-Null
        $res = Invoke-PocketRomOrganizePlan -Plan (New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 1000)
        $res.MovedCount | Should -Be 10
        @(Get-ChildItem -LiteralPath $script:common -File).Count | Should -Be 10   # back at root
        @(Get-ChildItem -LiteralPath $script:common -Directory).Count | Should -Be 0  # empty buckets pruned
    }

    It 'DryRun moves nothing on disk' {
        $plan = New-PocketRomOrganizePlan -Root $script:root -PlatformId 'gb' -MaxPerFolder 4
        $res = Invoke-PocketRomOrganizePlan -Plan $plan -DryRun
        $res.DryRun | Should -BeTrue
        @(Get-ChildItem -LiteralPath $script:common -File).Count | Should -Be 10   # untouched
    }
}
