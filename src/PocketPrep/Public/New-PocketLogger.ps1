function New-PocketLogger {
<#
.SYNOPSIS
    Creates a logger that records timestamped actions to a file and in memory.

.DESCRIPTION
    Returns a logger object used by Write-PocketLog. The in-memory Entries list lets
    tests assert on what was logged without reading files. Never log secrets.

.PARAMETER Path
    File path for the log. The parent directory is created if needed.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.Logger'
        Path       = $Path
        Entries    = [System.Collections.Generic.List[string]]::new()
    }
}
