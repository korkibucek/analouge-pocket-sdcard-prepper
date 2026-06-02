# Windows-only drive data provider. This is the ONLY function that touches real
# hardware/CIM. Every other function operates on plain objects, which is what makes
# the engine testable on any OS (tests inject a fake provider instead).

function Get-PocketRawDriveData {
    [CmdletBinding()]
    param()

    if (-not $IsWindows) {
        throw "Live drive detection is only supported on Windows. On other platforms use a fake SD root (test mode) or inject -DataProvider."
    }

    # Map each volume with a drive letter to its physical disk so we can read BusType
    # (USB/SD vs internal) and the disk's MediaType.
    $results = [System.Collections.Generic.List[object]]::new()

    $volumes = Get-Volume | Where-Object { $_.DriveLetter }
    foreach ($vol in $volumes) {
        $busType    = $null
        $mediaType  = $null
        $isRemovable = $false
        try {
            $partition = Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction Stop | Select-Object -First 1
            $disk      = $partition | Get-Disk -ErrorAction Stop
            $busType   = $disk.BusType
            $physical  = Get-PhysicalDisk -ErrorAction SilentlyContinue |
                Where-Object { $_.DeviceId -eq $disk.Number } | Select-Object -First 1
            if ($physical) { $mediaType = $physical.MediaType }
            # Treat USB and SD bus types as removable; also honour the legacy removable flag.
            $isRemovable = ($busType -in @('USB', 'SD', 'MMC')) -or
                           ($vol.DriveType -eq 'Removable')
        } catch {
            # Fall back to the volume's own DriveType if the disk lookup fails.
            $isRemovable = ($vol.DriveType -eq 'Removable')
        }

        $results.Add([pscustomobject]@{
            DriveLetter = "$($vol.DriveLetter):"
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
