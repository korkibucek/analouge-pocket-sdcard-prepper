BeforeAll {
    $repo = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

    # Captured-style fixtures (trimmed) representing a system disk + a USB SD card.
    $script:lsblkJson = @'
{ "blockdevices": [
   { "name":"vda","rm":false,"size":26843545600,"fsavail":null,"fstype":null,"mountpoint":null,"label":null,"tran":"virtio","hotplug":false,"type":"disk",
     "children":[ { "name":"vda1","rm":false,"size":25768738304,"fsavail":13618618368,"fstype":"ext4","mountpoint":"/","label":"cloudimg-rootfs","tran":"virtio","hotplug":false,"type":"part" } ] },
   { "name":"sdb","rm":true,"size":63864569856,"fsavail":null,"fstype":null,"mountpoint":null,"label":null,"tran":"usb","hotplug":true,"type":"disk",
     "children":[ { "name":"sdb1","rm":true,"size":63800000000,"fsavail":63700000000,"fstype":"exfat","mountpoint":"/media/user/POCKET","label":"POCKET","tran":"usb","hotplug":true,"type":"part" } ] }
] }
'@

    $script:macJson = @'
{ "SPStorageDataType": [
   { "_name":"Macintosh HD","mount_point":"/","file_system":"APFS","size_in_bytes":494384795648,"free_space_in_bytes":200000000000,
     "physical_drive":{ "is_internal_disk":"yes","protocol":"Apple Fabric","medium_type":"ssd","removable_media":"no" } },
   { "_name":"POCKET","mount_point":"/Volumes/POCKET","file_system":"ExFAT","size_in_bytes":63864569856,"free_space_in_bytes":63700000000,
     "physical_drive":{ "is_internal_disk":"no","protocol":"USB","medium_type":"ssd","removable_media":"yes" } }
] }
'@
}

Describe 'ConvertFrom-PocketLsblk (Linux)' {
    It 'extracts mounted volumes and marks the USB card removable' {
        InModuleScope PocketPrep -Parameters @{ json = $script:lsblkJson } {
            param($json)
            $r = ConvertFrom-PocketLsblk -Json $json
            $root = $r | Where-Object RootPath -eq '/'
            $card = $r | Where-Object RootPath -eq '/media/user/POCKET'
            $root.IsRemovable | Should -BeFalse
            $card.IsRemovable | Should -BeTrue
            $card.FileSystem  | Should -Be 'exfat'
            $card.Label       | Should -Be 'POCKET'
            $card.FreeBytes   | Should -Be 63700000000
        }
    }
}

Describe 'ConvertFrom-PocketSystemProfiler (macOS)' {
    It 'marks external USB volume removable and internal disk not' {
        InModuleScope PocketPrep -Parameters @{ json = $script:macJson } {
            param($json)
            $r = ConvertFrom-PocketSystemProfiler -Json $json
            ($r | Where-Object RootPath -eq '/').IsRemovable | Should -BeFalse
            $card = $r | Where-Object RootPath -eq '/Volumes/POCKET'
            $card.IsRemovable | Should -BeTrue
            $card.FileSystem  | Should -Be 'ExFAT'
            $card.BusType     | Should -Be 'USB'
        }
    }
}

Describe 'Get-PocketRemovableDrive with cross-platform records' {
    It 'filters to the removable card and exposes RootPath' {
        $records = InModuleScope PocketPrep -Parameters @{ json = $script:lsblkJson } {
            param($json) ConvertFrom-PocketLsblk -Json $json
        }
        $provider = { $records }.GetNewClosure()
        $drives = Get-PocketRemovableDrive -DataProvider $provider
        $drives.Count | Should -Be 1
        $drives[0].RootPath | Should -Be '/media/user/POCKET'
        $drives[0].IsRemovable | Should -BeTrue
    }
}
