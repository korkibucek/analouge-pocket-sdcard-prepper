#requires -Version 7.2
<#
.SYNOPSIS
    Runs the PocketPrep Pester test suite.
.DESCRIPTION
    Discovers and runs every *.Tests.ps1 under tests/. Exits non-zero on failure so
    it can be used in CI. Tests use fake drive data and temp folders only - they
    never touch real removable storage.
#>
[CmdletBinding()]
param(
    [string] $Path,
    [switch] $CI
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $Path) { $Path = Join-Path $repo 'tests' }

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' })) {
    Write-Host "Pester 5+ not found. Install it with: Install-Module Pester -Scope CurrentUser -Force" -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'Install-DevDeps.ps1')
}

Import-Module Pester -MinimumVersion 5.0.0

$config = New-PesterConfiguration
$config.Run.Path = $Path
$config.Output.Verbosity = if ($CI) { 'Detailed' } else { 'Normal' }
$config.Run.Exit = $true

Invoke-Pester -Configuration $config
