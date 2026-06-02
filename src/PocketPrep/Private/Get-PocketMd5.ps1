# Compute a lowercase MD5 hex digest for a file. Analogue publishes MD5 checksums
# for firmware, so MD5 (not a stronger hash) is what we must compare against.

function Get-PocketMd5 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found for hashing: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm MD5).Hash.ToLowerInvariant()
}
