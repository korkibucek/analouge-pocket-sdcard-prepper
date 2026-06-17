function Export-PocketSaveStateBackup {
<#
.SYNOPSIS
    Builds a zip of save states (a selection, or all) and returns its bytes - for backing
    up Memories to the user's local machine before a Memory Cleaner delete.

.DESCRIPTION
    Read-only: nothing on the card is modified. With -Paths, only those (containment-checked)
    save states are included; without -Paths, every save state under Memories/Save States is
    included. Entries are stored under "Save States/<relative path>" so the archive extracts
    straight back over Memories/. Returns the zip as a byte array plus a suggested file name;
    the web layer base64-encodes it for a browser download.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER Paths
    Optional card-relative paths to include; omit to back up every save state.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Position = 1)]
        [string[]] $Paths
    )

    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $fileName = "pocket-memories-$stamp.zip"
    $statesDir = Join-Path (Join-Path $Root 'Memories') 'Save States'
    $emptyBytes = [byte[]]@()

    if (-not (Test-Path -LiteralPath $statesDir -PathType Container)) {
        return [pscustomobject]@{ PSTypeName = 'PocketPrep.SaveStateBackup'; FileName = $fileName; Count = 0; Bytes = $emptyBytes }
    }
    $statesFull = (Resolve-Path -LiteralPath $statesDir).Path

    if ($PSBoundParameters.ContainsKey('Paths') -and @($Paths).Count -gt 0) {
        $entries = @((Resolve-PocketSaveStatePath -StatesFull $statesFull -Paths $Paths).Found)
    } else {
        $entries = @(Get-ChildItem -LiteralPath $statesDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{ RelativePath = $_.FullName.Substring($statesFull.Length).TrimStart([char]'\', [char]'/').Replace('\', '/'); File = $_ }
        })
    }
    if ($entries.Count -eq 0) {
        return [pscustomobject]@{ PSTypeName = 'PocketPrep.SaveStateBackup'; FileName = $fileName; Count = 0; Bytes = $emptyBytes }
    }

    # Build into a temp file, read the bytes back, then remove the temp.
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName() + '.zip')
    try {
        Write-PocketSaveStateZip -ZipPath $tmp -Entries $entries
        $bytes = [System.IO.File]::ReadAllBytes($tmp)
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    [pscustomobject]@{ PSTypeName = 'PocketPrep.SaveStateBackup'; FileName = $fileName; Count = $entries.Count; Bytes = $bytes }
}
