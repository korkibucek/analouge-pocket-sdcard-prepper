#requires -Version 7.2
<#
.SYNOPSIS
    Builds a versioned release zip for the Analogue Pocket SD Card Prepper.
.DESCRIPTION
    Packages the module, manifests, launcher, wizard, and docs into a clean zip under
    dist/. The zip contains a run-from-source layout - no compilation needed; the user
    only needs PowerShell 7.
#>
[CmdletBinding()]
param(
    [string] $OutputDirectory
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repo 'dist' }

$version = (Import-PowerShellDataFile (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1')).ModuleVersion
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("PocketPrep_" + [System.IO.Path]::GetRandomFileName())
$pkgRoot = Join-Path $stage "AnaloguePocketSDCardPrepper-$version"
New-Item -ItemType Directory -Path $pkgRoot -Force | Out-Null

foreach ($item in 'src', 'manifests', 'docs', 'examples', 'PocketPrep.cmd', 'README.md', 'CHANGELOG.md') {
    Copy-Item -Path (Join-Path $repo $item) -Destination $pkgRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$zip = Join-Path $OutputDirectory "AnaloguePocketSDCardPrepper-$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $pkgRoot '*') -DestinationPath $zip
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Release built: $zip"
