#requires -Version 7.2
<#
.SYNOPSIS
    Launches the Analogue Pocket SD Card Prepper web UI (local server).

.DESCRIPTION
    Thin wrapper that imports the PocketPrep module and starts the localhost web
    server. Works on Windows, Linux, and macOS. Copies files only; never formats or
    deletes. See Start-PocketPrepServer for the security model (127.0.0.1 + token).

.EXAMPLE
    pwsh ./src/Start-PocketPrepWeb.ps1
.EXAMPLE
    pwsh ./src/Start-PocketPrepWeb.ps1 -TestMode -DryRun
#>
[CmdletBinding()]
param(
    [string] $Root,
    [switch] $TestMode,
    [int]    $Port = 0,
    [switch] $DryRun,
    [switch] $NoBrowser,
    [switch] $IncludeFixed
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $here 'PocketPrep/PocketPrep.psd1') -Force

$params = @{ Port = $Port }
if ($PSBoundParameters.ContainsKey('Root')) { $params.Root = $Root }
if ($TestMode)     { $params.TestMode = $true }
if ($DryRun)       { $params.DryRun = $true }
if ($NoBrowser)    { $params.NoBrowser = $true }
if ($IncludeFixed) { $params.IncludeFixed = $true }

Start-PocketPrepServer @params
