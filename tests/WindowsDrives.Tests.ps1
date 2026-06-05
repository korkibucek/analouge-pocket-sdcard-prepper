BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force
}

Describe 'ConvertTo-PocketWindowsDriveRecord (pure classifier)' {
    It 'marks USB/SD/MMC bus types and the Removable DriveType as removable' {
        InModuleScope PocketPrep {
            (ConvertTo-PocketWindowsDriveRecord -DriveLetter 'E' -BusType 'USB'  -DriveType 'Fixed'     -Size 64GB -SizeRemaining 60GB).IsRemovable | Should -BeTrue
            (ConvertTo-PocketWindowsDriveRecord -DriveLetter 'F' -BusType 'SD'   -DriveType 'Removable' -Size 32GB -SizeRemaining 30GB).IsRemovable | Should -BeTrue
            (ConvertTo-PocketWindowsDriveRecord -DriveLetter 'G' -BusType 'SATA' -DriveType 'Removable' -Size 16GB -SizeRemaining 15GB).IsRemovable | Should -BeTrue
        }
    }
    It 'marks internal NVMe/SATA fixed disks as not removable' {
        InModuleScope PocketPrep {
            (ConvertTo-PocketWindowsDriveRecord -DriveLetter 'C' -BusType 'NVMe' -DriveType 'Fixed' -Size 1TB -SizeRemaining 200GB).IsRemovable | Should -BeFalse
            (ConvertTo-PocketWindowsDriveRecord -DriveLetter 'D' -BusType 'SATA' -DriveType 'Fixed' -Size 4TB -SizeRemaining 1TB).IsRemovable | Should -BeFalse
        }
    }
    It 'shapes DriveLetter and RootPath as X: and X:\' {
        InModuleScope PocketPrep {
            $r = ConvertTo-PocketWindowsDriveRecord -DriveLetter 'E' -BusType 'USB' -DriveType 'Fixed' -Size 1 -SizeRemaining 1
            $r.DriveLetter | Should -Be 'E:'
            $r.RootPath | Should -Be 'E:\'
        }
    }
}

Describe 'Live Windows drive detection' {
    It 'runs the real detection path without throwing and returns the expected shape' -Skip:(-not $IsWindows) {
        $drives = Get-PocketRemovableDrive -IncludeFixed
        # CI may have zero removable drives; the point is the live CIM path executes.
        foreach ($d in $drives) {
            $d.PSObject.Properties.Name | Should -Contain 'RootPath'
            $d.PSObject.Properties.Name | Should -Contain 'IsRemovable'
            $d.PSObject.Properties.Name | Should -Contain 'BusType'
            $d.DriveLetter | Should -Match ':$'
        }
        # The system drive must be present (fixed) when including fixed drives.
        @($drives).Count | Should -BeGreaterThan 0
    }
}
