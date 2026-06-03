function Clear-PocketCard {
<#
.SYNOPSIS
    DESTRUCTIVE (opt-in): deletes the contents of a card so it can be re-prepped.

.DESCRIPTION
    This is the ONLY function that deletes user data, and it is heavily gated. It will
    NOT run unless every safeguard passes:

      1. Safety re-check: the target must be a detected REMOVABLE volume that is not a
         system/protected volume (Test-PocketDriveSafety). A fixed disk needs the
         explicit advanced override; the system volume is never allowed.
      2. Typed confirmation: -ConfirmToken must exactly match the volume label or the
         resolved root path.
      3. It deletes the CONTENTS of the root only (never the root itself), and skips
         OS-managed entries it cannot/should not touch (e.g. System Volume Information).
      4. -DryRun lists exactly what would be removed without deleting anything.
      5. Every action is logged.

    Back up your saves first (Backup-PocketSaves). There is no undo.

.PARAMETER Root
    The card root / mountpoint to clean.

.PARAMETER ConfirmToken
    Must equal the volume label or the resolved root path, typed by the user.

.PARAMETER AllowAdvancedOverride
    Permit a non-removable volume (still never the system volume).

.PARAMETER DryRun
    List what would be removed without deleting anything.

.PARAMETER DataProvider
    Drive-data provider (for testing); defaults to live detection.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $ConfirmToken,
        [switch] $AllowAdvancedOverride,
        [switch] $DryRun,
        [scriptblock] $DataProvider,
        [psobject] $Logger
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Root path not found or not a folder: $Root"
    }
    $rootFull = (Resolve-Path -LiteralPath $Root).Path
    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    # --- Safeguard 1: the target must be a detected, safe, removable volume. ---
    $drives = if ($DataProvider) {
        Get-PocketRemovableDrive -DataProvider $DataProvider -IncludeFixed
    } else {
        Get-PocketRemovableDrive -IncludeFixed
    }
    $norm = { param($p) if ($p -eq '/') { '/' } else { ([string]$p).TrimEnd('\', '/') } }
    $drive = $drives | Where-Object {
        ((& $norm $_.RootPath) -ieq (& $norm $rootFull)) -or ((& $norm $_.DriveLetter) -ieq (& $norm $rootFull))
    } | Select-Object -First 1

    if (-not $drive) {
        throw "Refusing to clean '$rootFull': it is not a detected removable volume, so it cannot be verified safe."
    }
    $verdict = Test-PocketDriveSafety -Drive $drive -AllowAdvancedOverride:$AllowAdvancedOverride
    if (-not $verdict.Safe) {
        throw "Refusing to clean '$rootFull': $($verdict.Reasons -join ' ')"
    }

    # --- Safeguard 2: typed confirmation must match the label or the root path. ---
    $expected = @($drive.Label, $rootFull, (& $norm $rootFull)) | Where-Object { $_ }
    if ($ConfirmToken -notin $expected) {
        throw "Confirmation token did not match the volume label ('$($drive.Label)') or the root path. Refusing to clean."
    }

    # --- Enumerate contents, skipping OS-managed entries. ---
    $benign = $script:PocketDefaults.BenignRootEntries
    $entries = Get-ChildItem -LiteralPath $rootFull -Force -ErrorAction SilentlyContinue |
        Where-Object { $benign -notcontains $_.Name }

    $removed = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $entries) {
        $removed.Add($e.Name)
        if ($DryRun) {
            & $log "DRYRUN clean: would remove $($e.Name)" 'INFO'
        } else {
            & $log "CLEAN: removing $($e.Name)" 'WARN'
            Remove-Item -LiteralPath $e.FullName -Recurse -Force -ErrorAction Stop
        }
    }

    [pscustomobject]@{
        PSTypeName   = 'PocketPrep.CleanResult'
        Root         = $rootFull
        DryRun       = [bool]$DryRun
        RemovedCount = $removed.Count
        Removed      = $removed.ToArray()
        SkippedOsEntries = @($benign | Where-Object { Test-Path -LiteralPath (Join-Path $rootFull $_) })
    }
}
