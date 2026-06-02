BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    $script:fakeDrives = {
        @(
            [pscustomobject]@{ DriveLetter='E:'; Label='POCKET'; FileSystem='exFAT'; SizeBytes=64GB;  FreeBytes=63GB;  IsRemovable=$true;  BusType='SD';  MediaType='SSD' },
            [pscustomobject]@{ DriveLetter='F:'; Label='USBKEY'; FileSystem='FAT32'; SizeBytes=16GB;  FreeBytes=15GB;  IsRemovable=$true;  BusType='USB'; MediaType='Unspecified' },
            [pscustomobject]@{ DriveLetter='C:'; Label='OS';     FileSystem='NTFS';  SizeBytes=1TB;   FreeBytes=200GB; IsRemovable=$false; BusType='NVMe';MediaType='SSD' },
            [pscustomobject]@{ DriveLetter='D:'; Label='BACKUP'; FileSystem='NTFS';  SizeBytes=4TB;   FreeBytes=1TB;   IsRemovable=$false; BusType='SATA';MediaType='HDD' }
        )
    }
}

Describe 'Get-PocketRemovableDrive' {
    It 'returns only removable drives by default' {
        $r = Get-PocketRemovableDrive -DataProvider $script:fakeDrives
        $r.Count | Should -Be 2
        $r.DriveLetter | Should -Contain 'E:'
        $r.DriveLetter | Should -Contain 'F:'
        $r.DriveLetter | Should -Not -Contain 'C:'
    }

    It 'includes fixed drives only when -IncludeFixed is set' {
        $r = Get-PocketRemovableDrive -DataProvider $script:fakeDrives -IncludeFixed
        $r.Count | Should -Be 4
    }

    It 'normalises the drive object shape' {
        $d = (Get-PocketRemovableDrive -DataProvider $script:fakeDrives)[0]
        $d.PSObject.Properties.Name | Should -Contain 'DriveLetter'
        $d.PSObject.Properties.Name | Should -Contain 'FreeBytes'
        $d.PSObject.Properties.Name | Should -Contain 'BusType'
    }
}
