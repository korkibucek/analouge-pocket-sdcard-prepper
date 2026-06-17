function Get-PocketSaveStateGroupKey {
<#
.SYNOPSIS
    Computes the "game" group key for a save-state file, so the Memory Cleaner and the
    policy prune group identical states the same way.

.DESCRIPTION
    A game is identified by its directory plus the file's base name with a SINGLE trailing
    numeric counter stripped: "Game-1.sta", "Game_2.sta", "Game (3).sta" and "Game #4.sta"
    all belong to "game". A name with no numeric suffix is its own group.

.PARAMETER Directory
    The file's containing directory (its full path), used to keep same-named states in
    different folders apart.

.PARAMETER Name
    The file's leaf name (with extension).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $Directory,
        [Parameter(Mandatory, Position = 1)] [string] $Name
    )
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Name)
    $stripped = $base -replace '(\s*[-_#]\s*\d+|\s*\(\d+\))$', ''
    "$Directory|$($stripped.Trim().ToLowerInvariant())"
}
