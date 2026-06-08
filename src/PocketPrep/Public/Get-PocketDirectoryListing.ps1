function Get-PocketDirectoryListing {
<#
.SYNOPSIS
    Lists the sub-folders of a directory, for the web UI's folder picker.

.DESCRIPTION
    Read-only. Returns the resolved path, its parent (or null at a filesystem root), the
    immediate child directories, and the filesystem roots (drive letters on Windows;
    '/' and the home folder on Linux/macOS). Lists directory names only - never file
    contents. Defaults to the user's home folder when no path is given.

.PARAMETER Path
    The directory to list. Empty/blank or a missing path falls back to the home folder.
#>
    [CmdletBinding()]
    param([string] $Path)

    $homeDir = [Environment]::GetFolderPath('UserProfile')
    if ([string]::IsNullOrWhiteSpace($homeDir)) { $homeDir = [System.IO.Path]::GetTempPath() }

    # Filesystem roots / shortcuts the picker always offers.
    $roots = [System.Collections.Generic.List[object]]::new()
    if ($IsWindows) {
        foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
            if ($d.IsReady) { $roots.Add([pscustomobject]@{ Name = $d.Name; Path = $d.RootDirectory.FullName }) }
        }
    } else {
        $roots.Add([pscustomobject]@{ Name = '/'; Path = '/' })
    }
    if ($homeDir) { $roots.Add([pscustomobject]@{ Name = 'Home'; Path = $homeDir }) }

    $target = if ([string]::IsNullOrWhiteSpace($Path)) { $homeDir } else { $Path }
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { $target = $homeDir }
    $resolved = (Resolve-Path -LiteralPath $target).Path

    $dirs = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($d in (Get-ChildItem -LiteralPath $resolved -Directory -Force -ErrorAction Stop | Sort-Object Name)) {
            # Skip hidden/system dot-folders to keep the list useful.
            if ($d.Name.StartsWith('.')) { continue }
            $dirs.Add([pscustomobject]@{ Name = $d.Name; Path = $d.FullName })
        }
    } catch {
        # Permission denied / transient: return an empty list rather than throwing.
        $null = $_
    }

    $parent = Split-Path -Parent $resolved
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $resolved) { $parent = $null }

    [pscustomobject]@{
        PSTypeName  = 'PocketPrep.DirectoryListing'
        Path        = $resolved
        Parent      = $parent
        Directories = $dirs.ToArray()
        Roots       = $roots.ToArray()
    }
}
