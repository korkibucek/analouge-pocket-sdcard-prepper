# Pure parser for `system_profiler SPStorageDataType -json` (macOS). Kept separate from
# the command call so it can be unit-tested with captured fixtures on any OS.

function ConvertFrom-PocketSystemProfiler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Json
    )

    $data = $Json | ConvertFrom-Json
    $records = [System.Collections.Generic.List[object]]::new()

    foreach ($vol in @($data.SPStorageDataType)) {
        if (-not $vol) { continue }
        $mount = [string]$vol.mount_point
        if (-not $mount) { continue }

        $pd = $vol.physical_drive
        $internal  = if ($pd) { ("$($pd.is_internal_disk)" -ieq 'yes') } else { $true }
        $removableMedia = if ($pd) { ("$($pd.removable_media)" -ieq 'yes') } else { $false }
        $protocol  = if ($pd) { [string]$pd.protocol } else { '' }
        $mediaType = if ($pd -and $pd.medium_type) { [string]$pd.medium_type } elseif ($pd) { [string]$pd.media_name } else { '' }

        # External (not internal) OR media flagged removable => treat as removable.
        $removable = (-not $internal) -or $removableMedia -or ($protocol -ieq 'usb')

        $records.Add([pscustomobject]@{
            DriveLetter = $mount
            RootPath    = $mount
            Label       = [string]$vol._name
            FileSystem  = [string]$vol.file_system
            SizeBytes   = [int64]($vol.size_in_bytes ?? 0)
            FreeBytes   = [int64]($vol.free_space_in_bytes ?? 0)
            IsRemovable = [bool]$removable
            BusType     = $protocol
            MediaType   = $mediaType
        })
    }
    return $records
}
