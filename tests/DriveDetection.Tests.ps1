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

    It 'flags a fixed exFAT/FAT32 card-sized volume as a likely card; not the big NTFS disk' {
        $provider = {
            @(
                [pscustomobject]@{ DriveLetter='G:'; RootPath='G:\'; Label='CARD';   FileSystem='exFAT'; SizeBytes=64GB; FreeBytes=64GB; IsRemovable=$false; BusType='SATA'; MediaType='' },
                [pscustomobject]@{ DriveLetter='C:'; RootPath='C:\'; Label='OS';     FileSystem='NTFS';  SizeBytes=1TB;  FreeBytes=200GB; IsRemovable=$false; BusType='NVMe'; MediaType='' },
                [pscustomobject]@{ DriveLetter='H:'; RootPath='H:\'; Label='RAW';    FileSystem='';      SizeBytes=32GB; FreeBytes=0;     IsRemovable=$false; BusType='USB';  MediaType='' }
            )
        }
        $all = Get-PocketRemovableDrive -DataProvider $provider -IncludeFixed
        ($all | Where-Object RootPath -eq 'G:\').LikelyRemovableCard | Should -BeTrue
        ($all | Where-Object RootPath -eq 'C:\').LikelyRemovableCard | Should -BeFalse   # NTFS / large
        ($all | Where-Object RootPath -eq 'H:\').LikelyRemovableCard | Should -BeFalse   # RAW (unknown fs) -> not assumed a card
    }

    It 'lists a RAW/unformatted volume without throwing' {
        $provider = { @([pscustomobject]@{ DriveLetter='H:'; RootPath='H:\'; Label=''; FileSystem=''; SizeBytes=32GB; FreeBytes=0; IsRemovable=$true; BusType='USB'; MediaType='' }) }
        { Get-PocketRemovableDrive -DataProvider $provider } | Should -Not -Throw
        (Get-PocketRemovableDrive -DataProvider $provider).Count | Should -Be 1
    }
}
