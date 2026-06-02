#requires -Version 7.2
<#
.SYNOPSIS
    Interactive wizard for the Analogue Pocket SD Card Prepper.

.DESCRIPTION
    Guides a user through preparing an SD card for an Analogue Pocket:
      1. Detect/select a drive (or use a fake SD root in test mode)
      2. Safety checks (never targets the system drive; fixed disks need override)
      3. Filesystem + emptiness checks
      4. Install firmware (official download or a local file), optional
      5. Create the openFPGA folder structure
      6. Per-system ROM import
      7. Final summary + log

    This tool copies USER-PROVIDED ROMs only. It does not download or supply ROMs,
    and it never formats, wipes, repartitions, or deletes your data.

.PARAMETER TestMode
    Use -Root as an ordinary folder (a fake SD root) instead of a real card.

.PARAMETER Root
    The drive root or fake SD root. In test mode this defaults to a temp folder.

.PARAMETER DryRun
    Plan all actions without writing anything.

.PARAMETER AllowAdvancedOverride
    Permit a non-removable drive to be selected (never the system drive).

.EXAMPLE
    pwsh ./src/Start-PocketPrep.ps1 -TestMode

.EXAMPLE
    pwsh ./src/Start-PocketPrep.ps1
#>
[CmdletBinding()]
param(
    [switch] $TestMode,
    [string] $Root,
    [switch] $DryRun,
    [switch] $AllowAdvancedOverride,
    [string] $FirmwareManifest,
    [string] $SystemsManifest,
    [string] $CoresManifest,
    [string] $LogDirectory
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $here 'PocketPrep/PocketPrep.psd1') -Force

$repoRoot = Split-Path -Parent $here
if (-not $FirmwareManifest) { $FirmwareManifest = Join-Path $repoRoot 'manifests/firmware.json' }
if (-not $SystemsManifest)  { $SystemsManifest  = Join-Path $repoRoot 'manifests/systems.json' }
if (-not $CoresManifest)    { $CoresManifest    = Join-Path $repoRoot 'manifests/cores.json' }
if (-not $LogDirectory)     { $LogDirectory     = Join-Path ([System.IO.Path]::GetTempPath()) 'PocketPrepLogs' }

function Write-Banner($text) { Write-Host ""; Write-Host "=== $text ===" -ForegroundColor Cyan }
function Confirm-YesNo($prompt, [bool]$default = $false) {
    $suffix = if ($default) { '[Y/n]' } else { '[y/N]' }
    $a = Read-Host "$prompt $suffix"
    if ($null -eq $a) { return $default }   # EOF / non-interactive input
    $a = $a.Trim()
    if ([string]::IsNullOrEmpty($a)) { return $default }
    return $a -match '^[Yy]'
}

Write-Host "Analogue Pocket SD Card Prepper" -ForegroundColor Green
Write-Host "This tool only copies files into folders. It never formats, wipes, or deletes your data." -ForegroundColor Yellow
Write-Host "It does NOT provide or download ROMs - it copies ROMs you already own." -ForegroundColor Yellow
if ($DryRun) { Write-Host "DRY-RUN: no files will be written." -ForegroundColor Magenta }

# --- Step 1/2: choose target -------------------------------------------------
Write-Banner '1. Select target'
if ($TestMode) {
    if (-not $Root) { $Root = Join-Path ([System.IO.Path]::GetTempPath()) 'PocketSDTest' }
    Write-Host "Test mode: using fake SD root '$Root'."
    $target = New-PocketTarget -Root $Root -TestMode
} else {
    $drives = Get-PocketRemovableDrive -IncludeFixed:$AllowAdvancedOverride
    if (-not $drives -or $drives.Count -eq 0) {
        Write-Host "No removable drives detected. Insert an SD card, or run with -TestMode." -ForegroundColor Red
        return
    }
    Write-Host "Detected drives:"
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d = $drives[$i]
        $sz = [math]::Round($d.SizeBytes / 1GB, 1)
        $fr = [math]::Round($d.FreeBytes / 1GB, 1)
        $rem = if ($d.IsRemovable) { 'removable' } else { 'FIXED' }
        Write-Host ("  [{0}] {1}  '{2}'  {3}  {4} GB ({5} GB free)  bus={6}  {7}" -f `
            $i, $d.DriveLetter, $d.Label, $d.FileSystem, $sz, $fr, $d.BusType, $rem)
    }
    $sel = Read-Host "Select a drive by number"
    if ($sel -notmatch '^\d+$' -or [int]$sel -ge $drives.Count) {
        Write-Host "Invalid selection. Aborting." -ForegroundColor Red; return
    }
    $chosen = $drives[[int]$sel]

    Write-Banner '2. Safety check'
    $verdict = Test-PocketDriveSafety -Drive $chosen -AllowAdvancedOverride:$AllowAdvancedOverride
    foreach ($r in $verdict.Reasons) { Write-Host "  - $r" }
    if (-not $verdict.Safe) {
        Write-Host "This drive is not safe to use. Aborting." -ForegroundColor Red; return
    }
    if ($verdict.RequiresOverride) {
        if (-not (Confirm-YesNo "This drive needed the advanced override. Continue?" $false)) { return }
    }
    $target = New-PocketTarget -Root ($chosen.DriveLetter + '\')
}

# Logger
$logName = "pocketprep-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date)
$logger = New-PocketLogger -Path (Join-Path $LogDirectory $logName)
Write-PocketLog -Logger $logger -Message "Run started. Target=$($target.Root) TestMode=$($target.IsTestMode) DryRun=$DryRun" | Out-Null

# --- Step 3/4: filesystem + emptiness ---------------------------------------
Write-Banner '3. Filesystem & emptiness'
if (-not $target.IsTestMode -and $chosen) {
    $fsv = Test-PocketFilesystem -FileSystem $chosen.FileSystem
    Write-Host "Filesystem: $($fsv.FileSystem) - acceptable: $($fsv.Acceptable)"
    if ($fsv.Remediation) { Write-Host "  $($fsv.Remediation)" -ForegroundColor Yellow }
    if (-not $fsv.Acceptable) {
        if (-not (Confirm-YesNo "Filesystem is not acceptable. Continue anyway?" $false)) { return }
    }
}
$empty = Test-PocketCardEmpty -Root $target.Root
if ($empty.IsEmpty) {
    Write-Host "Card appears empty - good."
} else {
    Write-Host "Card is NOT empty. Top-level items ($($empty.EntryCount)):" -ForegroundColor Yellow
    $empty.Entries | Select-Object -First 15 | ForEach-Object { Write-Host "  - $_" }
    if (-not (Confirm-YesNo "Existing files will be left in place (nothing is deleted). Continue?" $false)) { return }
}

# --- Step 5: firmware --------------------------------------------------------
Write-Banner '4. Firmware'
$firmwareResult = $null
if (Confirm-YesNo "Install Pocket firmware now?" $true) {
    $manifest = Get-PocketFirmwareManifest -Path $FirmwareManifest
    $release  = Resolve-PocketFirmwareRelease -Manifest $manifest
    Write-Host "Latest firmware in manifest: v$($release.version) ($($release.releaseDate))."
    $offline = Confirm-YesNo "Use a firmware file you already downloaded (offline mode)?" $false
    try {
        if ($offline) {
            $lf = Read-Host "Path to firmware .bin"
            $firmwareResult = Install-PocketFirmware -Root $target.Root -LocalFile $lf -OfflineRelease $release -DryRun:$DryRun -Logger $logger
        } else {
            $firmwareResult = Install-PocketFirmware -Root $target.Root -Release $release -DryRun:$DryRun -Logger $logger
        }
        Write-Host "Firmware: v$($firmwareResult.Version) -> $($firmwareResult.Destination)" -ForegroundColor Green
        $firmwareResult.Warnings | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
    } catch {
        Write-Host "Firmware step failed: $_" -ForegroundColor Red
        Write-PocketLog -Logger $logger -Message "Firmware step failed: $_" -Level ERROR | Out-Null
    }
}

# --- Step 7: folder structure ------------------------------------------------
Write-Banner '5. Folder structure'
$folderResult = New-PocketFolderStructure -Root $target.Root -DryRun:$DryRun
Write-Host "Created: $($folderResult.Created -join ', ')"
Write-Host "Already present: $($folderResult.Existing -join ', ')"
Write-PocketLog -Logger $logger -Message "Folders created: $($folderResult.Created -join ',')" | Out-Null

# --- Step 5b: openFPGA cores (optional) -------------------------------------
Write-Banner '6. openFPGA cores (optional)'
Write-Host "Cores are made by independent authors under their own licences." -ForegroundColor Yellow
$coreResults = [System.Collections.Generic.List[object]]::new()
if ((Test-Path -LiteralPath $CoresManifest) -and (Confirm-YesNo "Install any openFPGA cores now?" $false)) {
    $cores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest)
    foreach ($core in $cores) {
        if (-not (Confirm-YesNo "Install $($core.DisplayName) [$($core.Id)]?" $false)) { continue }
        $useLocal = Confirm-YesNo "  Use a core .zip you already downloaded (offline)? (No = download from GitHub)" $false
        try {
            if ($useLocal) {
                $cz = Read-Host "  Path to $($core.Identifier) .zip (from $($core.Homepage))"
                if ([string]::IsNullOrWhiteSpace($cz)) { continue }
                $cr = Install-PocketCore -Root $target.Root -LocalZip $cz -Core $core -DryRun:$DryRun -Logger $logger
            } else {
                $cr = Install-PocketCore -Root $target.Root -Core $core -Download -DryRun:$DryRun -Logger $logger
            }
            Write-Host "  $($core.Identifier): placed $($cr.PlacedCount), skipped $($cr.SkippedCount) (v$($cr.Version))." -ForegroundColor Green
            $coreResults.Add($cr)
        } catch {
            Write-Host "  Core install failed: $_" -ForegroundColor Red
            Write-PocketLog -Logger $logger -Message "Core $($core.Id) failed: $_" -Level ERROR | Out-Null
        }
    }
}

# --- Step 8/9: ROM import ----------------------------------------------------
Write-Banner '7. ROM import'
$systems = Get-PocketSystem -Path $SystemsManifest
$romResults = [System.Collections.Generic.List[object]]::new()
foreach ($sys in $systems) {
    if (-not (Confirm-YesNo "Configure $($sys.DisplayName) [$($sys.Id)]? (exts: $($sys.SupportedExtensions -join ' '))" $false)) {
        continue
    }
    $src = Read-Host "  Source ROM folder for $($sys.DisplayName) (blank to skip)"
    if ([string]::IsNullOrWhiteSpace($src)) { continue }
    if (-not (Test-Path -LiteralPath $src -PathType Container)) {
        Write-Host "  Folder not found, skipping." -ForegroundColor Yellow; continue
    }
    $recurse = Confirm-YesNo "  Search subfolders too?" $false
    $plan = New-PocketRomCopyPlan -System $sys -SourceFolder $src -Root $target.Root -Recurse:$recurse
    Write-Host "  Found $($plan.FileCount) matching file(s) ($([math]::Round($plan.TotalBytes/1MB,1)) MB). Skipping $($plan.SkippedNonMatching) non-matching."
    if ($plan.FileCount -eq 0) { continue }
    if (Confirm-YesNo "  Copy $($plan.FileCount) file(s) to $($plan.Destination)?" $true) {
        $res = Invoke-PocketRomCopyPlan -Plan $plan -DryRun:$DryRun -Logger $logger
        Write-Host "  Copied $($res.CopiedCount), skipped $($res.SkippedCount), failed $($res.FailedCount)." -ForegroundColor Green
        $romResults.Add($res)
    }
}

# --- Step 10/11: summary + log ----------------------------------------------
Write-Banner '8. Summary'
$summary = New-PocketInstallSummary -Target $target -FirmwareResult $firmwareResult -FolderResult $folderResult -RomResults $romResults.ToArray() -CoreResults $coreResults.ToArray()
Write-Host $summary.Text
Write-PocketLog -Logger $logger -Message $summary.Text | Out-Null
Write-Host ""
Write-Host "Log saved to: $($logger.Path)"

if (-not $DryRun -and (Confirm-YesNo "Also save a copy of the log to the SD card?" $true)) {
    try {
        Copy-Item -LiteralPath $logger.Path -Destination (Join-Path $target.Root $logName) -Force
        Write-Host "Log copied to card."
    } catch { Write-Host "Could not copy log to card: $_" -ForegroundColor Yellow }
}
Write-Host "Done. When your Pocket arrives, insert the card and power on." -ForegroundColor Green
