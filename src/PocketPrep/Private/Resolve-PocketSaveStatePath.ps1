function Resolve-PocketSaveStatePath {
<#
.SYNOPSIS
    Resolves card-relative save-state paths to files, refusing anything outside
    Memories/Save States (traversal / absolute paths / non-existent).

.DESCRIPTION
    The Memory Cleaner deletes an explicit, user-chosen list of save states. This validates
    each requested relative path so a malformed or hostile path can never reach a file
    outside the save-states tree. Returns Found (resolved FileInfo + RelativePath) and
    Rejected (the input strings that did not resolve to a real file inside the tree).

.PARAMETER StatesFull
    The resolved full path of Memories/Save States.

.PARAMETER Paths
    Card-relative paths (under Memories/Save States), forward- or back-slashed.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [string] $StatesFull,
        [Parameter(Position = 1)] [string[]] $Paths
    )
    $found = [System.Collections.Generic.List[object]]::new()
    $rejected = [System.Collections.Generic.List[string]]::new()
    $rootWithSep = $StatesFull.TrimEnd([char]'\', [char]'/') + [System.IO.Path]::DirectorySeparatorChar
    foreach ($p in @($Paths)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $candidate = Join-Path $StatesFull ($p -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        # Canonicalise WITHOUT requiring existence, then containment-check, then existence.
        $full = [System.IO.Path]::GetFullPath($candidate)
        if (($full -ne $StatesFull) -and $full.StartsWith($rootWithSep, [System.StringComparison]::Ordinal) -and (Test-Path -LiteralPath $full -PathType Leaf)) {
            $relNorm = $full.Substring($StatesFull.Length).TrimStart([char]'\', [char]'/').Replace('\', '/')
            $found.Add([pscustomobject]@{ RelativePath = $relNorm; File = (Get-Item -LiteralPath $full) })
        } else {
            $rejected.Add([string]$p)
        }
    }
    [pscustomobject]@{ Found = $found.ToArray(); Rejected = $rejected.ToArray() }
}
