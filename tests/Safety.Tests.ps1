BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    function New-Drive($letter, $removable, $size) {
        [pscustomobject]@{ DriveLetter=$letter; Label='X'; FileSystem='exFAT'; SizeBytes=$size; FreeBytes=$size; IsRemovable=$removable; BusType='USB'; MediaType='' }
    }
}

Describe 'Test-PocketDriveSafety' {
    It 'always rejects the system drive, even with override' {
        $v = Test-PocketDriveSafety -Drive (New-Drive 'C:' $false 1TB) -SystemDrive 'C:' -AllowAdvancedOverride
        $v.Safe | Should -BeFalse
        $v.IsSystemDrive | Should -BeTrue
    }

    It 'accepts a normal removable card' {
        $v = Test-PocketDriveSafety -Drive (New-Drive 'E:' $true 64GB) -SystemDrive 'C:'
        $v.Safe | Should -BeTrue
        $v.RequiresOverride | Should -BeFalse
    }

    It 'rejects a fixed drive without override' {
        $v = Test-PocketDriveSafety -Drive (New-Drive 'D:' $false 256GB) -SystemDrive 'C:'
        $v.Safe | Should -BeFalse
        $v.RequiresOverride | Should -BeTrue
    }

    It 'allows a fixed drive only with explicit override' {
        $v = Test-PocketDriveSafety -Drive (New-Drive 'D:' $false 256GB) -SystemDrive 'C:' -AllowAdvancedOverride
        $v.Safe | Should -BeTrue
        $v.RequiresOverride | Should -BeTrue
        $v.OverrideApplied | Should -BeTrue
    }

    It 'flags a suspiciously large non-removable disk' {
        $v = Test-PocketDriveSafety -Drive (New-Drive 'D:' $false 4TB) -SystemDrive 'C:' -AllowAdvancedOverride
        ($v.Reasons -join ' ') | Should -Match 'internal or backup'
    }

    It 'rejects a drive with no letter' {
        $v = Test-PocketDriveSafety -Drive (New-Drive '' $true 64GB) -SystemDrive 'C:'
        $v.Safe | Should -BeFalse
    }
}
