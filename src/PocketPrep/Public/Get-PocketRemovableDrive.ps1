function Get-PocketRemovableDrive {
<#
.SYNOPSIS
    Lists drives suitable for selection as an Analogue Pocket SD card.

.DESCRIPTION
    Returns normalised drive-info objects. By default only removable media is
    returned, so a wrong selection cannot target an internal disk. The actual
    hardware query is isolated in the -DataProvider script block, which defaults
    to the Windows CIM/Storage provider; tests inject a fake provider instead.

.PARAMETER IncludeFixed
    Also return non-removable (fixed) drives. Intended for the advanced override
    path only - callers must still pass safety checks.

.PARAMETER DataProvider
    A script block returning raw drive records. Used for testing and for unusual
    environments. Each record must expose DriveLetter, Label, FileSystem,
    SizeBytes, FreeBytes, IsRemovable, BusType, MediaType.

.EXAMPLE
    Get-PocketRemovableDrive
#>
    [CmdletBinding()]
    param(
        [switch] $IncludeFixed,
        [scriptblock] $DataProvider
    )

    $raw = if ($DataProvider) { & $DataProvider } else { Get-PocketRawDriveData }

    $drives = foreach ($r in $raw) {
        [pscustomobject]@{
            PSTypeName  = 'PocketPrep.Drive'
            DriveLetter = [string]$r.DriveLetter
            RootPath    = if ($r.PSObject.Properties['RootPath'] -and $r.RootPath) { [string]$r.RootPath } else { [string]$r.DriveLetter }
            Label       = [string]$r.Label
            FileSystem  = [string]$r.FileSystem
            SizeBytes   = [int64]$r.SizeBytes
            FreeBytes   = [int64]$r.FreeBytes
            IsRemovable = [bool]$r.IsRemovable
            BusType     = [string]$r.BusType
            MediaType   = [string]$r.MediaType
        }
    }

    if (-not $IncludeFixed) {
        $drives = $drives | Where-Object { $_.IsRemovable }
    }

    return @($drives)
}
