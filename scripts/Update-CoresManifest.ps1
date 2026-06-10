#requires -Version 7.2
<#
.SYNOPSIS
    Regenerates manifests/cores.json from the community openFPGA Cores Inventory.
.DESCRIPTION
    Fetches the canonical inventory and writes manifests/cores.json covering every
    GitHub-hosted core. Re-run this to pick up new/updated cores (see docs/manifests.md).
    Does not download cores; only repository coordinates + metadata are stored.
.PARAMETER InventoryUrl
    The inventory JSON URL (v1 API by default).
.PARAMETER OutFile
    Where to write the manifest (defaults to manifests/cores.json).
#>
[CmdletBinding()]
param(
    [string] $InventoryUrl = 'https://joshcampbell191.github.io/openfpga-cores-inventory/api/v1/analogue-pocket/cores.json',
    [string] $OutFile,
    [string] $SupplementFile
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutFile) { $OutFile = Join-Path $repo 'manifests/cores.json' }
if (-not $SupplementFile) { $SupplementFile = Join-Path $repo 'manifests/cores-supplement.json' }

Write-Host "Fetching inventory: $InventoryUrl"
$inv = Invoke-RestMethod -Uri $InventoryUrl -Headers @{ 'User-Agent' = 'PocketPrep' } -TimeoutSec 60

# Platforms whose core needs a copyrighted system BIOS the user must supply (NEVER
# downloaded by this tool). Keyed by platformId -> required BIOS file name(s).
$biosByPlatform = @{
    'ng' = @('neogeo.zip')
}

# Releases that ship SEVERAL zip assets need a regex to pick the right one - otherwise the
# first-zip default installs the wrong build (the GB-GBC repo lists GBC first so classic GB
# was never installed; agg23's repos list the MiSTer build first). Keyed by inventory
# identifier; repos matching $assetPatternByRepo apply to every entry from that repo.
$assetPatternByIdentifier = @{
    'Spiritualized.GB'  = '_GB_'
    'Spiritualized.GBC' = '_GBC_'
}
# opengateware arcade repos ship a pocket build zip AND a rom-recipes zip (naming varies:
# <core>_pocket-*.zip or arcade-<x>-pocket-*.zip); always pick the Pocket build regardless
# of asset order. PowerShell -match is case-insensitive, so 'pocket' covers both.
$resolveAssetPattern = {
    param($identifier, $owner, $repo)
    if ($assetPatternByIdentifier.ContainsKey($identifier)) { return $assetPatternByIdentifier[$identifier] }
    if ($owner -ieq 'opengateware' -and $repo -like 'arcade-*') { return 'pocket' }
    return $null
}

$seen = @{}
$cores = foreach ($e in ($inv.data | Where-Object { $_.repository.platform -eq 'github' } | Sort-Object identifier)) {
    # Stable slug id from the identifier (schema: ^[a-z0-9_-]+$); dedupe defensively.
    $id = ($e.identifier -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLowerInvariant()
    $base = $id; $n = 2
    while ($seen.ContainsKey($id)) { $id = "$base-$n"; $n++ }
    $seen[$id] = $true

    $plat = $e.release.platform
    $platformIds = @($e.release.assets | ForEach-Object { $_.platform } | Where-Object { $_ } | Select-Object -Unique)
    $meta = @(
        if ($plat.category)     { $plat.category }
        if ($plat.name)         { $plat.name }
        if ($plat.manufacturer) { "by $($plat.manufacturer)" }
        if ($plat.year)         { "($($plat.year))" }
    ) -join ' '

    # Flag a BIOS requirement when any of the core's platforms needs one.
    $biosFiles = @($platformIds | ForEach-Object { $biosByPlatform[$_] } | Where-Object { $_ } | Select-Object -Unique)

    $entry = [ordered]@{
        id           = $id
        identifier   = $e.identifier
        displayName  = "$($plat.name) [$($e.repository.owner)]"
        platformIds  = $platformIds
        owner        = $e.repository.owner
        repo         = $e.repository.name
        homepage     = "https://github.com/$($e.repository.owner)/$($e.repository.name)"
        biosRequired = ($biosFiles.Count -gt 0)
        biosFiles    = $biosFiles
        notes        = "From the openFPGA Cores Inventory. $meta".Trim()
    }
    $ap = & $resolveAssetPattern $e.identifier $e.repository.owner $e.repository.name
    if ($ap) { $entry.assetPattern = $ap }
    $entry
}
$cores = @($cores)

# Merge the curated supplement (community cores not in the inventory but verified to have a
# downloadable openFPGA release zip). Inventory entries win on an owner/repo conflict.
if (Test-Path -LiteralPath $SupplementFile) {
    # Dedupe by (repo, assetPattern): two entries may legitimately share a repo when its
    # release ships several zips (e.g. budude2's repo carries both a GB and a GBC zip).
    $haveRepos = @{}
    foreach ($c in $cores) { $haveRepos[("$($c.owner)/$($c.repo)".ToLowerInvariant() + '|' + [string]$c.assetPattern)] = $true }
    $supp = (Get-Content -LiteralPath $SupplementFile -Raw | ConvertFrom-Json).cores
    $added = 0
    foreach ($s in @($supp)) {
        $key = "$($s.owner)/$($s.repo)".ToLowerInvariant() + '|' + [string]$s.assetPattern
        if ($haveRepos.ContainsKey($key)) { continue }
        $haveRepos[$key] = $true
        $entry = [ordered]@{
            id           = $s.id
            identifier   = $s.identifier
            displayName  = $s.displayName
            platformIds  = @($s.platformIds)
            owner        = $s.owner
            repo         = $s.repo
            homepage     = $s.homepage
            biosRequired = [bool]$s.biosRequired
            biosFiles    = @($s.biosFiles)
            notes        = [string]$s.notes
        }
        if ($s.assetPattern) { $entry.assetPattern = [string]$s.assetPattern }
        $cores += $entry
        $added++
    }
    $cores = @($cores | Sort-Object { $_.identifier })
    Write-Host "Merged $added supplement core(s) from $SupplementFile"
}

$out = [ordered]@{
    '$schema'  = './schemas/cores.schema.json'
    '_comment' = "Generated from the community openFPGA Cores Inventory ($InventoryUrl) by scripts/Update-CoresManifest.ps1. Cores are made by independent authors under their own licences; this tool downloads each core's GitHub release at install time and bundles nothing. Re-run the script to refresh. platformIds come from the inventory's asset platforms and may be empty for cores with no ROM platform."
    cores      = $cores
}
($out | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $OutFile -Encoding utf8
Write-Host "Wrote $($cores.Count) cores to $OutFile" -ForegroundColor Green
