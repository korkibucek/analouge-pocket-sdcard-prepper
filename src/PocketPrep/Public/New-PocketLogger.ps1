function New-PocketLogger {
<#
.SYNOPSIS
    Creates a logger that records timestamped actions to a file and in memory.

.DESCRIPTION
    Returns a logger object used by Write-PocketLog. The in-memory Entries list lets
    tests assert on what was logged without reading files. Never log secrets.

.PARAMETER Path
    File path for the log. The parent directory is created if needed.

.PARAMETER MaxKeep
    Retention: keep at most this many existing pocketprep-*.log files in the log
    directory (oldest are pruned) so logs don't accumulate forever. Default 20; 0 disables.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [int] $MaxKeep = 20
    )

    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Retention: prune oldest logs in the directory (keep the newest MaxKeep). The new log
    # about to be written counts toward the limit, so keep MaxKeep-1 existing ones.
    if ($MaxKeep -gt 0 -and $dir -and (Test-Path -LiteralPath $dir)) {
        $existing = @(Get-ChildItem -LiteralPath $dir -Filter 'pocketprep-*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($existing.Count -ge $MaxKeep) {
            $existing | Select-Object -Skip ([Math]::Max($MaxKeep - 1, 0)) |
                ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.Logger'
        Path       = $Path
        Entries    = [System.Collections.Generic.List[string]]::new()
    }
}
