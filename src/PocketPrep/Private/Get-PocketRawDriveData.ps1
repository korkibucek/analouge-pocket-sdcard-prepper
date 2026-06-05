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

# Pure classifier: turns Windows volume/disk facts into a normalised drive record.
# Kept separate from the CIM calls so the removable logic is unit-testable on any OS.
function ConvertTo-PocketWindowsDriveRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $DriveLetter,
        [string] $Label,
        [string] $FileSystem,
        [int64]  $Size,
        [int64]  $SizeRemaining,
        [string] $BusType,
        [string] $MediaType,
        [string] $DriveType
    )
    $isRemovable = ($BusType -in @('USB', 'SD', 'MMC')) -or ($DriveType -eq 'Removable')
    [pscustomobject]@{
        DriveLetter = "${DriveLetter}:"
        RootPath    = "${DriveLetter}:\"
        Label       = $Label
        FileSystem  = $FileSystem
        SizeBytes   = $Size
        FreeBytes   = $SizeRemaining
        IsRemovable = [bool]$isRemovable
        BusType     = $BusType
        MediaType   = $MediaType
    }
}

function Get-PocketRawDriveDataWindows {
    $results = [System.Collections.Generic.List[object]]::new()
    $volumes = Get-Volume | Where-Object { $_.DriveLetter }
    foreach ($vol in $volumes) {
        $busType = $null; $mediaType = $null
        try {
            $partition = Get-Partition -DriveLetter $vol.DriveLetter -ErrorAction Stop | Select-Object -First 1
            $disk      = $partition | Get-Disk -ErrorAction Stop
            $busType   = $disk.BusType
            $physical  = Get-PhysicalDisk -ErrorAction SilentlyContinue |
                Where-Object { $_.DeviceId -eq $disk.Number } | Select-Object -First 1
            if ($physical) { $mediaType = $physical.MediaType }
        } catch {
            # Locked/RAW/unusual volumes can throw on the disk lookup; fall back to the
            # volume's own DriveType for the removable decision.
            $busType = $null
        }
        $results.Add((ConvertTo-PocketWindowsDriveRecord -DriveLetter ([string]$vol.DriveLetter) `
            -Label ([string]$vol.FileSystemLabel) -FileSystem ([string]$vol.FileSystem) `
            -Size ([int64]$vol.Size) -SizeRemaining ([int64]$vol.SizeRemaining) `
            -BusType ([string]$busType) -MediaType ([string]$mediaType) -DriveType ([string]$vol.DriveType)))
    }
    return $results
}
