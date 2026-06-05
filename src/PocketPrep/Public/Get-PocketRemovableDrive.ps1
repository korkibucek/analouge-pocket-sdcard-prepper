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

    $acceptableFs = $script:PocketDefaults.AcceptableFilesystems   # FAT32 / exFAT
    $drives = foreach ($r in $raw) {
        $size = [int64]$r.SizeBytes
        $fs   = [string]$r.FileSystem
        $removable = [bool]$r.IsRemovable
        # Many built-in/USB card readers present the card as a FIXED disk, so it's hidden
        # by default. Flag a fixed volume that nonetheless looks like an SD card (a Pocket-
        # compatible filesystem and a card-sized capacity) so the UI can guide the user to
        # the advanced override instead of saying "no drives found".
        $likelyCard = (-not $removable) -and ($size -gt 0 -and $size -le 2TB) -and
                      ($acceptableFs -contains $fs.Trim().ToUpperInvariant())
        [pscustomobject]@{
            PSTypeName  = 'PocketPrep.Drive'
            DriveLetter = [string]$r.DriveLetter
            RootPath    = if ($r.PSObject.Properties['RootPath'] -and $r.RootPath) { [string]$r.RootPath } else { [string]$r.DriveLetter }
            Label       = [string]$r.Label
            FileSystem  = $fs
            SizeBytes   = $size
            FreeBytes   = [int64]$r.FreeBytes
            IsRemovable = $removable
            BusType     = [string]$r.BusType
            MediaType   = [string]$r.MediaType
            LikelyRemovableCard = [bool]$likelyCard
        }
    }

    if (-not $IncludeFixed) {
        $drives = $drives | Where-Object { $_.IsRemovable }
    }

    return @($drives)
}
