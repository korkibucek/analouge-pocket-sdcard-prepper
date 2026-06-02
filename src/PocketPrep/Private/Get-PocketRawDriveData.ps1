# Drive data provider. This is the ONLY function that runs OS-specific commands to
# enumerate volumes. Every other function operates on plain objects, which keeps the
# engine testable on any OS (tests inject a fake provider or fixtures into the pure
# ConvertFrom-Pocket* parsers).

function Get-PocketRawDriveData {
    [CmdletBinding()]
    param()

    if ($IsWindows) {
        return Get-PocketRawDriveDataWindows
    } elseif ($IsLinux) {
        $json = & lsblk -J -b -o NAME,RM,SIZE,FSAVAIL,FSTYPE,MOUNTPOINT,LABEL,TRAN,HOTPLUG,TYPE 2>$null | Out-String
        if (-not $json.Trim()) { throw "lsblk produced no output; is it installed?" }
        return ConvertFrom-PocketLsblk -Json $json
    } elseif ($IsMacOS) {
        $json = & system_profiler -json SPStorageDataType 2>$null | Out-String
        if (-not $json.Trim()) { throw "system_profiler produced no output." }
        return ConvertFrom-PocketSystemProfiler -Json $json
    } else {
        throw "Unsupported platform for live drive detection. Use a fake SD root (test mode) or inject -DataProvider."
    }
}

function Get-PocketRawDriveDataWindows {
    $results = [System.Collections.Generic.List[object]]::new()
    $volumes = Get-Volume | Where-Object { $_.DriveLetter }
    foreach ($vol in $volumes) {
        $busType = $null; $mediaType = $null; $isRemovable = $false
        try {
            $partition = Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction Stop | Select-Object -First 1
            $disk      = $partition | Get-Disk -ErrorAction Stop
            $busType   = $disk.BusType
            $physical  = Get-PhysicalDisk -ErrorAction SilentlyContinue |
                Where-Object { $_.DeviceId -eq $disk.Number } | Select-Object -First 1
            if ($physical) { $mediaType = $physical.MediaType }
            $isRemovable = ($busType -in @('USB', 'SD', 'MMC')) -or ($vol.DriveType -eq 'Removable')
        } catch {
            $isRemovable = ($vol.DriveType -eq 'Removable')
        }
        $results.Add([pscustomobject]@{
            DriveLetter = "$($vol.DriveLetter):"
            RootPath    = "$($vol.DriveLetter):\"
            Label       = $vol.FileSystemLabel
            FileSystem  = $vol.FileSystem
            SizeBytes   = [int64]$vol.Size
            FreeBytes   = [int64]$vol.SizeRemaining
            IsRemovable = [bool]$isRemovable
            BusType     = "$busType"
            MediaType   = "$mediaType"
        })
    }
    return $results
}
