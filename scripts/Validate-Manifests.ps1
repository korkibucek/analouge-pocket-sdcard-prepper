#requires -Version 7.2
<#
.SYNOPSIS
    Validates the firmware, systems, and cores manifests.
.DESCRIPTION
    Loads each manifest through the engine loaders (which enforce structure) and runs a
    few extra consistency checks. Exits non-zero with a clear message on the first
    problem; exits 0 when all manifests are valid. Suitable for CI / pre-commit.
#>
[CmdletBinding()]
param(
    [string] $ManifestDirectory
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $ManifestDirectory) { $ManifestDirectory = Join-Path $repo 'manifests' }
Import-Module (Join-Path $repo 'src/PocketPrep/PocketPrep.psd1') -Force

$problems = [System.Collections.Generic.List[string]]::new()

# Firmware
try {
    $fw = Get-PocketFirmwareManifest -Path (Join-Path $ManifestDirectory 'firmware.json')
    $null = Resolve-PocketFirmwareRelease -Manifest $fw   # 'latest' must resolve
    Write-Host "firmware.json: OK ($(@($fw.releases).Count) release(s), latest $($fw.latest))" -ForegroundColor Green
} catch { $problems.Add("firmware.json: $_") }

# Systems
try {
    $systems = Get-PocketSystem -Path (Join-Path $ManifestDirectory 'systems.json')
    foreach ($s in $systems) {
        if (-not $s.PlatformId) { $problems.Add("systems.json: '$($s.Id)' has empty platformId") }
    }
    Write-Host "systems.json: OK ($(@($systems).Count) systems)" -ForegroundColor Green
} catch { $problems.Add("systems.json: $_") }

# Cores
try {
    $coresPath = Join-Path $ManifestDirectory 'cores.json'
    if (Test-Path -LiteralPath $coresPath) {
        $cores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $coresPath)
        foreach ($c in $cores) {
            if ($c.Identifier -notmatch '^[^.]+\.[^.]+') { $problems.Add("cores.json: '$($c.Id)' identifier '$($c.Identifier)' is not Author.CoreName") }
            if (-not $c.Owner -or -not $c.Repo)          { $problems.Add("cores.json: '$($c.Id)' missing owner/repo") }
        }
        Write-Host "cores.json: OK ($(@($cores).Count) cores)" -ForegroundColor Green
    }
} catch { $problems.Add("cores.json: $_") }

if ($problems.Count -gt 0) {
    Write-Host "`nManifest validation FAILED:" -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "`nAll manifests valid." -ForegroundColor Green
