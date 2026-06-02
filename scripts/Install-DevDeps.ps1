#requires -Version 7.2
<#
.SYNOPSIS
    Installs developer dependencies (Pester 5) for running the test suite.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

if (Get-Module -ListAvailable -Name Pester | Where-Object { $_.Version -ge [version]'5.0.0' }) {
    Write-Host "Pester 5+ already installed."
    return
}
Write-Host "Installing Pester 5 (CurrentUser scope)..."
Install-Module -Name Pester -Force -Scope CurrentUser -SkipPublisherCheck -MinimumVersion 5.0.0
Write-Host "Done."
