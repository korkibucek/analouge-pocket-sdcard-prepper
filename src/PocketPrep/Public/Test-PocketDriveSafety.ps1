function Test-PocketDriveSafety {
<#
.SYNOPSIS
    Decides whether a drive is safe to use as the target SD card.

.DESCRIPTION
    Pure decision function (no side effects). It never formats or deletes anything;
    it only classifies a drive. Rules, in order of severity:

      * The system drive (e.g. C:) is ALWAYS rejected and can never be overridden.
      * A non-removable (fixed) drive is rejected unless -AllowAdvancedOverride.
      * A non-removable drive larger than the large-disk threshold is flagged as
        an internal/backup-disk risk and also needs the override.
      * A removable drive with no obvious risk is safe.

    Note: this tool only ever copies files into folders. It performs no wipe,
    format, or repartition, so "safe" here means "safe to copy onto".

.PARAMETER Drive
    A drive-info object from Get-PocketRemovableDrive.

.PARAMETER AllowAdvancedOverride
    Permit a non-removable drive to pass (still never the system drive).

.PARAMETER SystemDrive
    Override the detected system drive letter (mainly for testing). Defaults to
    the SystemDrive environment value, e.g. "C:".
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Drive,

        [switch] $AllowAdvancedOverride,

        [string] $SystemDrive
    )

    process {
        if (-not $SystemDrive) {
            $SystemDrive = if ($env:SystemDrive) { $env:SystemDrive } else { 'C:' }
        }
        $SystemDrive = $SystemDrive.TrimEnd('\')

        $reasons          = [System.Collections.Generic.List[string]]::new()
        $isSystemDrive    = $false
        $requiresOverride = $false
        $safe             = $true

        $letter = ([string]$Drive.DriveLetter).TrimEnd('\')

        if ([string]::IsNullOrWhiteSpace($letter)) {
            $reasons.Add('Drive has no drive letter; cannot target it safely.')
            $safe = $false
        }

        if ($letter -and ($letter -ieq $SystemDrive)) {
            $isSystemDrive = $true
            $safe = $false
            $reasons.Add("This is the Windows system drive ($SystemDrive). It can never be used as the SD card target.")
        }

        if (-not $isSystemDrive) {
            if (-not $Drive.IsRemovable) {
                $requiresOverride = $true
                $reasons.Add('Drive does not appear to be removable media. Fixed/internal disks are blocked unless the advanced override is used.')

                if ($Drive.SizeBytes -gt $script:PocketDefaults.LargeNonRemovableThresholdBytes) {
                    $reasons.Add("Drive is large for an SD card ($([math]::Round($Drive.SizeBytes/1GB,0)) GB) and is not removable. This looks like an internal or backup disk.")
                }

                if (-not $AllowAdvancedOverride) {
                    $safe = $false
                } else {
                    $reasons.Add('Advanced override supplied: proceeding on a non-removable drive at your own risk.')
                }
            }
        }

        if ($safe -and $reasons.Count -eq 0) {
            $reasons.Add('Drive appears to be removable media and is safe to copy onto.')
        }

        [pscustomobject]@{
            PSTypeName       = 'PocketPrep.SafetyVerdict'
            DriveLetter      = $letter
            Safe             = $safe
            IsSystemDrive    = $isSystemDrive
            RequiresOverride = $requiresOverride
            OverrideApplied  = [bool]$AllowAdvancedOverride
            Reasons          = $reasons.ToArray()
        }
    }
}
