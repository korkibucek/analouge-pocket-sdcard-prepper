function Test-PocketFilesystem {
<#
.SYNOPSIS
    Checks whether a filesystem is acceptable for the Analogue Pocket.

.DESCRIPTION
    The Pocket accepts FAT32 or exFAT (source: Analogue "Updating Firmware" guide).
    exFAT is recommended because FAT32 cannot store files larger than 4 GB, which
    some cores need. This function only reports; it never formats anything.

.PARAMETER FileSystem
    The filesystem name to evaluate (e.g. "exFAT", "FAT32", "NTFS").

.PARAMETER Drive
    Alternatively, a drive-info object whose FileSystem property is evaluated.
#>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName', Position = 0)]
        [AllowEmptyString()]
        [string] $FileSystem,

        [Parameter(Mandatory, ParameterSetName = 'ByDrive', ValueFromPipeline)]
        [psobject] $Drive
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByDrive') {
            $FileSystem = [string]$Drive.FileSystem
        }

        $normalized = ($FileSystem ?? '').Trim().ToUpperInvariant()
        $acceptable = $script:PocketDefaults.AcceptableFilesystems -contains $normalized
        $recommended = $script:PocketDefaults.RecommendedFilesystem

        $remediation = $null
        if (-not $acceptable) {
            $shown = if ([string]::IsNullOrWhiteSpace($FileSystem)) { '(unknown)' } else { $FileSystem }
            $remediation = "Filesystem '$shown' is not supported. Format the card as $recommended (recommended) or FAT32 using Windows Disk Management or 'Format' in File Explorer, then re-run. This tool does not format cards for you."
        } elseif ($normalized -eq 'FAT32') {
            $remediation = "FAT32 is supported, but it cannot hold files larger than 4 GB. If you plan to use cores with large assets, reformat as exFAT."
        }

        [pscustomobject]@{
            PSTypeName  = 'PocketPrep.FilesystemVerdict'
            FileSystem  = $FileSystem
            Acceptable  = $acceptable
            Recommended = $recommended
            Remediation = $remediation
        }
    }
}
