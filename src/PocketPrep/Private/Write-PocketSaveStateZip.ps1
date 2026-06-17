function Write-PocketSaveStateZip {
<#
.SYNOPSIS
    Writes a set of save-state files into a zip, under "Save States/<relative path>" entries
    (so the archive can be extracted straight back over Memories/).

.PARAMETER ZipPath
    Destination .zip path (created; must not already exist).

.PARAMETER Entries
    Objects with .File (FileInfo) and .RelativePath (forward-slash, card-relative).
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $ZipPath,
        [Parameter(Mandatory, Position = 1)] [object[]] $Entries
    )
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($e in $Entries) {
            $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $e.File.FullName, ("Save States/" + $e.RelativePath))
        }
    } finally { $zip.Dispose() }
}
