function Test-PocketDriveSafety {
<#
.SYNOPSIS
    Decides whether a drive/volume is safe to use as the target SD card, on any OS.

.DESCRIPTION
    Pure decision function (no side effects). It never formats or deletes anything; it
    only classifies a volume. Rules, in order of severity:

      * A system volume is ALWAYS rejected and can never be overridden. On Windows that
        is the system drive (e.g. C:); on Linux/macOS it is a protected mountpoint such
        as /, /boot, /usr, /home, /System, or the volume holding your home directory.
      * A non-removable (fixed) volume is rejected unless -AllowAdvancedOverride.
      * A non-removable volume larger than the large-disk threshold is flagged as an
        internal/backup-disk risk and also needs the override.
      * A removable volume with no obvious risk is safe.

.PARAMETER Drive
    A drive-info object from Get-PocketRemovableDrive.

.PARAMETER AllowAdvancedOverride
    Permit a non-removable volume to pass (never a system volume).

.PARAMETER SystemDrive
    Override the detected Windows system drive letter (mainly for testing).

.PARAMETER ProtectedRoot
    Override the set of protected mountpoints (mainly for testing). When supplied, the
    OS defaults are not used.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [psobject] $Drive,

        [switch] $AllowAdvancedOverride,

        [string] $SystemDrive,

        [string[]] $ProtectedRoot
    )

    process {
        # Identifier to evaluate: prefer RootPath (mountpoint / X:\), fall back to letter.
        $id = if ($Drive.PSObject.Properties['RootPath'] -and $Drive.RootPath) {
            [string]$Drive.RootPath
        } else {
            [string]$Drive.DriveLetter
        }

        $normalize = {
            param($p)
            $p = ([string]$p).Trim()
            if ($p -eq '/') { return '/' }
            return $p.TrimEnd('\', '/')
        }
        $idNorm = & $normalize $id

        # Build the protected set.
        $protected = [System.Collections.Generic.List[string]]::new()
        if ($PSBoundParameters.ContainsKey('ProtectedRoot')) {
            foreach ($p in $ProtectedRoot) { $protected.Add((& $normalize $p)) }
        } elseif ($IsLinux -or $IsMacOS) {
            foreach ($p in '/', '/boot', '/boot/efi', '/usr', '/var', '/etc', '/home',
                           '/opt', '/srv', '/nix', '/System', '/System/Volumes/Data',
                           '/private', '/Applications', '/Users') {
                $protected.Add($p)
            }
            if ($HOME) { $protected.Add((& $normalize $HOME)) }
        }

        # System drive (Windows, or explicitly provided for tests).
        $sysDrive = $SystemDrive
        if (-not $sysDrive -and $IsWindows) { $sysDrive = $env:SystemDrive }
        if ($sysDrive) { $protected.Add((& $normalize $sysDrive)) }

        $reasons          = [System.Collections.Generic.List[string]]::new()
        $isSystemVolume   = $false
        $requiresOverride = $false
        $safe             = $true

        if ([string]::IsNullOrWhiteSpace($idNorm)) {
            $reasons.Add('Volume has no path/letter; cannot target it safely.')
            $safe = $false
        }

        if ($idNorm -and ($protected | Where-Object { $_ -ieq $idNorm })) {
            $isSystemVolume = $true
            $safe = $false
            $reasons.Add("This is a system/protected volume ($idNorm). It can never be used as the SD card target.")
        }

        if (-not $isSystemVolume) {
            if (-not $Drive.IsRemovable) {
                $requiresOverride = $true
                $reasons.Add('Volume does not appear to be removable media. Fixed/internal disks are blocked unless the advanced override is used.')

                if ($Drive.SizeBytes -gt $script:PocketDefaults.LargeNonRemovableThresholdBytes) {
                    $reasons.Add("Volume is large for an SD card ($([math]::Round($Drive.SizeBytes/1GB,0)) GB) and is not removable. This looks like an internal or backup disk.")
                }
                if (-not $AllowAdvancedOverride) {
                    $safe = $false
                } else {
                    $reasons.Add('Advanced override supplied: proceeding on a non-removable volume at your own risk.')
                }
            }
        }

        if ($safe -and $reasons.Count -eq 0) {
            $reasons.Add('Volume appears to be removable media and is safe to copy onto.')
        }

        [pscustomobject]@{
            PSTypeName       = 'PocketPrep.SafetyVerdict'
            DriveLetter      = [string]$Drive.DriveLetter
            RootPath         = $idNorm
            Safe             = $safe
            IsSystemDrive    = $isSystemVolume   # kept for backwards compatibility
            IsSystemVolume   = $isSystemVolume
            RequiresOverride = $requiresOverride
            OverrideApplied  = [bool]$AllowAdvancedOverride
            Reasons          = $reasons.ToArray()
        }
    }
}
