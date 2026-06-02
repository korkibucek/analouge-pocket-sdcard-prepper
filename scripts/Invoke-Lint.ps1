#requires -Version 7.2
<#
.SYNOPSIS
    Runs PSScriptAnalyzer over the module and scripts using the repo ruleset.
.DESCRIPTION
    Fails (exit 1) if any Error/Warning-severity findings remain. Installs
    PSScriptAnalyzer if missing. Used locally and in CI.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Host 'Installing PSScriptAnalyzer...'
    Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
}
Import-Module PSScriptAnalyzer

$settings = Join-Path $repo 'PSScriptAnalyzerSettings.psd1'
$targets  = @((Join-Path $repo 'src'), (Join-Path $repo 'scripts'))

$findings = foreach ($t in $targets) {
    Invoke-ScriptAnalyzer -Path $t -Recurse -Settings $settings
}
$findings = @($findings)

if ($findings.Count -gt 0) {
    $findings | Select-Object @{n='File';e={Split-Path $_.ScriptName -Leaf}}, Line, Severity, RuleName, Message |
        Format-Table -AutoSize -Wrap | Out-String | Write-Host
    Write-Host "PSScriptAnalyzer found $($findings.Count) issue(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'PSScriptAnalyzer: clean.' -ForegroundColor Green
