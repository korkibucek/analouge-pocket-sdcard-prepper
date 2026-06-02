function Test-PocketCoreZip {
<#
.SYNOPSIS
    Inspects an openFPGA core zip without extracting it.

.DESCRIPTION
    Confirms the zip looks like an openFPGA core package: it must contain at least one
    of the top-level folders Assets/, Cores/, or Platforms/. Optionally checks that a
    specific core folder (Cores/<identifier>/) is present. Also detects unsafe entries
    (absolute paths or '..' traversal) so a malicious zip cannot escape the SD root.

.PARAMETER Path
    Path to the core .zip file.

.PARAMETER ExpectedIdentifier
    Optional Author.CoreName expected under Cores/.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [string] $ExpectedIdentifier
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Core zip not found: $Path"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    try {
        $names = $zip.Entries | ForEach-Object { $_.FullName }
    } finally {
        $zip.Dispose()
    }

    $known = @('Assets', 'Cores', 'Platforms', 'Presets', 'Settings')
    $topLevel = $names |
        ForEach-Object { ($_ -split '[\\/]')[0] } |
        Where-Object { $_ } |
        Select-Object -Unique

    $openFpgaFolders = $topLevel | Where-Object { $known -contains $_ }
    $hasStructure = @($openFpgaFolders | Where-Object { $_ -in 'Assets', 'Cores', 'Platforms' }).Count -gt 0

    $unsafe = @($names | Where-Object {
        $_ -match '(^|[\\/])\.\.([\\/]|$)' -or $_ -match '^([A-Za-z]:|[\\/])'
    })

    $hasCore = $true
    if ($ExpectedIdentifier) {
        $needle = "Cores/$ExpectedIdentifier/"
        $hasCore = @($names | Where-Object { ($_ -replace '\\', '/') -like "$needle*" }).Count -gt 0
    }

    [pscustomobject]@{
        PSTypeName       = 'PocketPrep.CoreZipVerdict'
        Path             = (Resolve-Path -LiteralPath $Path).Path
        TopLevelFolders  = @($openFpgaFolders)
        HasStructure     = $hasStructure
        HasExpectedCore  = $hasCore
        UnsafeEntries    = $unsafe
        Valid            = ($hasStructure -and $hasCore -and $unsafe.Count -eq 0)
    }
}
