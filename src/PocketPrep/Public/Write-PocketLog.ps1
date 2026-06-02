function Write-PocketLog {
<#
.SYNOPSIS
    Appends a timestamped line to a PocketPrep logger (file + memory).

.PARAMETER Logger
    A logger object from New-PocketLogger.

.PARAMETER Message
    The message to record. Do not pass secrets.

.PARAMETER Level
    Severity label: INFO, WARN, or ERROR. Default INFO.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $Logger,

        [Parameter(Mandatory, Position = 0)]
        [string] $Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string] $Level = 'INFO'
    )

    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $Logger.Entries.Add($line)
    try {
        Add-Content -LiteralPath $Logger.Path -Value $line -ErrorAction Stop
    } catch {
        Write-Warning "Could not write to log file '$($Logger.Path)': $_"
    }
    return $line
}
