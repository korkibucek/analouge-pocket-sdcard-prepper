function Remove-PocketSaveState {
<#
.SYNOPSIS
    Deletes an explicit, user-chosen list of save states - backed up first, guarded.

.DESCRIPTION
    The selection-driven counterpart to Invoke-PocketSaveStatePrune: instead of a policy,
    the caller passes the exact relative paths to remove (the Memory Cleaner's checkbox
    selection). Like the prune, it is one of only a few operations that delete user data,
    so it is fenced the same way:

      - It touches ONLY files under Memories/Save States. Every requested path is resolved
        and containment-checked; anything that escapes the tree, is absolute, or does not
        exist is rejected (reported in Skipped), never deleted.
      - Every file is ALWAYS backed up into a zip (pocketprep/save-backups/) before it is
        deleted - the backup cannot be switched off, so a delete is recoverable by
        extracting the zip back over Memories/.
      - -DryRun previews the exact files and deletes/backs-up nothing.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER Paths
    Card-relative paths (under Memories/Save States) to delete.

.PARAMETER DryRun
    Report the exact files that would be deleted; delete and back up nothing.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Deliberately guarded destructive op: mandatory backup zip + -DryRun preview + confirm-gated API.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Position = 1)]
        [string[]] $Paths,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    $result = [pscustomobject]@{
        PSTypeName = 'PocketPrep.SaveStateDeleteResult'
        Examined = @($Paths).Count; DeleteCount = 0; Deleted = @(); Skipped = @(); BackupZip = $null; DryRun = [bool]$DryRun
    }

    $statesDir = Join-Path (Join-Path $Root 'Memories') 'Save States'
    if (-not (Test-Path -LiteralPath $statesDir -PathType Container)) {
        $result.Skipped = @($Paths)   # nothing exists to delete
        return $result
    }
    $statesFull = (Resolve-Path -LiteralPath $statesDir).Path

    $resolved = Resolve-PocketSaveStatePath -StatesFull $statesFull -Paths $Paths
    $toDelete = @($resolved.Found)
    $result.Skipped = @($resolved.Rejected)
    if ($toDelete.Count -eq 0) { return $result }

    if (-not $DryRun) {
        # MANDATORY backup before any deletion - a delete is always recoverable.
        $backupDir = Join-Path (Join-Path $Root 'pocketprep') 'save-backups'
        if (-not (Test-Path -LiteralPath $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
        $backupZip = Join-Path $backupDir "save-states-$stamp.zip"
        $n = 2
        while (Test-Path -LiteralPath $backupZip) { $backupZip = Join-Path $backupDir "save-states-$stamp-$n.zip"; $n++ }
        Write-PocketSaveStateZip -ZipPath $backupZip -Entries $toDelete
        $result.BackupZip = $backupZip
        # Delete only after the backup zip is fully written.
        foreach ($e in $toDelete) {
            Remove-Item -LiteralPath $e.File.FullName -Force
            & $log "DELETE save state $($e.RelativePath)" 'WARN'
        }
        & $log "Memory cleaner: deleted $($toDelete.Count) save state(s) (backed up to $backupZip)" 'WARN'
    }

    $result.DeleteCount = $toDelete.Count
    $result.Deleted = @($toDelete | ForEach-Object { $_.RelativePath })
    $result
}
