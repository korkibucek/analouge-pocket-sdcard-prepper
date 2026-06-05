function Backup-PocketSaves {
<#
.SYNOPSIS
    Copies the card's Saves/ (and optionally Memories/) to a backup folder.

.DESCRIPTION
    Read-only with respect to the card: it copies save data off the card into a
    destination folder (a timestamped subfolder is created). Useful before re-prepping
    a used card. Never deletes anything. Supports -DryRun.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER Destination
    Folder to write the backup into. A timestamped subfolder is created beneath it.

.PARAMETER Stamp
    Label for the timestamped subfolder (callers pass a timestamp; defaults to 'backup').

.PARAMETER IncludeMemories
    Also back up the Memories/ folder.

.PARAMETER DryRun
    Report what would be copied without writing.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = '"Saves" is the literal Analogue Pocket folder name, not a generic plural.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $Destination,
        [string] $Stamp = 'backup',
        [switch] $IncludeMemories,
        [switch] $DryRun
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "SD root path not found or not a folder: $Root"
    }

    $folders = @('Saves')
    if ($IncludeMemories) { $folders += 'Memories' }

    $backupRoot = Join-Path $Destination "PocketSaves-$Stamp"
    $copied = [System.Collections.Generic.List[string]]::new()

    foreach ($f in $folders) {
        $src = Join-Path $Root $f
        if (-not (Test-Path -LiteralPath $src -PathType Container)) { continue }
        # Mirror Root/<folder>/... into backupRoot/<folder>/... (preserve the folder name).
        $res = Copy-PocketTree -Source $src -Destination (Join-Path $backupRoot $f) -DryRun:$DryRun
        foreach ($rel in $res.Copied) { $copied.Add((Join-Path $f $rel)) }
    }

    [pscustomobject]@{
        PSTypeName  = 'PocketPrep.SaveBackupResult'
        Root        = (Resolve-Path -LiteralPath $Root).Path
        Destination = $backupRoot
        DryRun      = [bool]$DryRun
        FileCount   = $copied.Count
        Files       = $copied.ToArray()
    }
}
