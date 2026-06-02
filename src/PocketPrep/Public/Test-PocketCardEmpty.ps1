function Test-PocketCardEmpty {
<#
.SYNOPSIS
    Reports whether an SD root (or fake SD root folder) is empty / safe to use.

.DESCRIPTION
    Lists top-level entries under the root, ignoring benign OS housekeeping items
    (e.g. "System Volume Information", ".Trashes"). It only inspects; it never
    deletes. The caller decides what to do when the card is not empty.

.PARAMETER Root
    Path to the SD card root or a fake SD root folder used in test mode.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "SD root path not found or not a folder: $Root"
    }

    $benign = $script:PocketDefaults.BenignRootEntries
    $entries = Get-ChildItem -LiteralPath $Root -Force -ErrorAction SilentlyContinue

    $userEntries = foreach ($e in $entries) {
        if ($benign -notcontains $e.Name) { $e.Name }
    }
    $userEntries = @($userEntries)

    [pscustomobject]@{
        PSTypeName    = 'PocketPrep.EmptyVerdict'
        Root          = (Resolve-Path -LiteralPath $Root).Path
        IsEmpty       = ($userEntries.Count -eq 0)
        EntryCount    = $userEntries.Count
        Entries       = $userEntries
        IgnoredCount  = (@($entries).Count - $userEntries.Count)
    }
}
