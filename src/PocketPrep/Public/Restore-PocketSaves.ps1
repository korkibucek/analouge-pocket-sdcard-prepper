function Restore-PocketSaves {
<#
.SYNOPSIS
    Restores a save backup (from Backup-PocketSaves) onto a card.

.DESCRIPTION
    Copies the backup's folder tree back onto the card root, preserving structure.
    Existing files are skipped unless -Overwrite (never silently clobbered). Supports
    -DryRun. Never deletes anything.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER Source
    A backup folder produced by Backup-PocketSaves (containing Saves/ and/or Memories/).

.PARAMETER Overwrite
    Overwrite files that already exist on the card.

.PARAMETER DryRun
    Report what would be restored without writing.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = '"Saves" is the literal Analogue Pocket folder name, not a generic plural.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $Source,
        [switch] $Overwrite,
        [switch] $DryRun
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container))   { throw "SD root path not found: $Root" }
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Backup source not found: $Source" }

    $srcFull = (Resolve-Path -LiteralPath $Source).Path
    $rootFull = (Resolve-Path -LiteralPath $Root).Path
    $res = Copy-PocketTree -Source $srcFull -Destination $rootFull -Overwrite:$Overwrite -DryRun:$DryRun
    $restored = $res.Copied
    $skipped  = $res.Skipped

    [pscustomobject]@{
        PSTypeName    = 'PocketPrep.SaveRestoreResult'
        Root          = $rootFull
        Source        = $srcFull
        DryRun        = [bool]$DryRun
        RestoredCount = @($restored).Count
        SkippedCount  = @($skipped).Count
        Restored      = @($restored)
        Skipped       = @($skipped)
    }
}
