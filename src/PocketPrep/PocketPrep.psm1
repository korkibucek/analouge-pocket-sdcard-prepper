# PocketPrep module loader.
# Dot-sources every .ps1 under Private/ then Public/, and exports the public functions.
# Keeping one function per file keeps the engine readable and unit-testable.

$ErrorActionPreference = 'Stop'

$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    } catch {
        throw "Failed to load PocketPrep function file '$($file.FullName)': $_"
    }
}

Export-ModuleMember -Function $public.BaseName
