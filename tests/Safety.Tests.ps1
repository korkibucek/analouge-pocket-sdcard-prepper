BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    function New-Drive($letter, $removable, $size) {
        [pscustomobject]@{ DriveLetter=$letter; Label='X'; FileSystem='exFAT'; SizeBytes=$size; FreeBytes=$size; IsRemovable=$removable; BusType='USB'; MediaType='' }
    }
    function New-MountDrive($root, $removable, $size) {
        [pscustomobject]@{ DriveLetter=$root; RootPath=$root; Label='X'; FileSystem='exFAT'; SizeBytes=$size; FreeBytes=$size; IsRemovable=$removable; BusType='USB'; MediaType='' }
    }
    $script:nixProtected = '/','/boot','/boot/efi','/usr','/home','/System'
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

Describe 'Test-PocketDriveSafety (Linux/macOS mountpoints)' {
    It 'rejects the root filesystem / even with override' {
        $v = Test-PocketDriveSafety -Drive (New-MountDrive '/' $false 1TB) -ProtectedRoot $script:nixProtected -AllowAdvancedOverride
        $v.Safe | Should -BeFalse
        $v.IsSystemVolume | Should -BeTrue
    }
    It 'rejects a protected mountpoint like /boot' {
        (Test-PocketDriveSafety -Drive (New-MountDrive '/boot' $true 512MB) -ProtectedRoot $script:nixProtected).Safe | Should -BeFalse
    }
    It 'accepts a removable card mounted under /media' {
        $v = Test-PocketDriveSafety -Drive (New-MountDrive '/media/user/POCKET' $true 64GB) -ProtectedRoot $script:nixProtected
        $v.Safe | Should -BeTrue
        $v.RootPath | Should -Be '/media/user/POCKET'
    }
    It 'accepts a macOS removable volume under /Volumes' {
        (Test-PocketDriveSafety -Drive (New-MountDrive '/Volumes/POCKET' $true 64GB) -ProtectedRoot $script:nixProtected).Safe | Should -BeTrue
    }
    It 'requires override for a fixed mountpoint not in the protected set' {
        $v = Test-PocketDriveSafety -Drive (New-MountDrive '/mnt/data' $false 2TB) -ProtectedRoot $script:nixProtected
        $v.Safe | Should -BeFalse
        $v.RequiresOverride | Should -BeTrue
    }
}
