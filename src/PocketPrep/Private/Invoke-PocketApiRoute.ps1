# Pure REST dispatcher. Maps (method, path, body, state) to a { Status; Body } result
# with no sockets involved, so the entire API surface is unit-testable. The HttpListener
# wrapper (Start-PocketPrepServer) is a thin layer over this.

function Invoke-PocketApiRoute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        [psobject] $Body,
        [Parameter(Mandatory)] [hashtable] $State
    )

    $target = [pscustomobject]@{ Root = $State.Root; IsTestMode = [bool]$State.IsTestMode }
    $key = "$($Method.ToUpperInvariant()) $Path"

    try {
        switch -Regex ($key) {
            '^GET /api/health$' {
                return @{ Status = 200; Body = @{
                    ok = $true; product = 'Analogue Pocket SD Card Prepper'
                    root = $State.Root; testMode = [bool]$State.IsTestMode; dryRun = [bool]$State.DryRun
                    targetReady = [bool]$State.TargetReady
                } }
            }
            '^POST /api/target$' {
                if ($Body.testMode) {
                    $rp = [string]$Body.rootPath
                    if (-not $rp) { return @{ Status = 400; Body = @{ error = 'Missing rootPath for test mode.' } } }
                    if (-not (Test-Path -LiteralPath $rp)) { New-Item -ItemType Directory -Path $rp -Force | Out-Null }
                    $State.Root = (Resolve-Path -LiteralPath $rp).Path
                    $State.IsTestMode = $true; $State.TargetReady = $true
                    return @{ Status = 200; Body = @{ root = $State.Root; isTestMode = $true; ready = $true } }
                }
                if (-not $Body.drive) { return @{ Status = 400; Body = @{ error = 'Missing drive.' } } }
                $v = Test-PocketDriveSafety -Drive $Body.drive -AllowAdvancedOverride:([bool]$Body.allowOverride)
                if (-not $v.Safe) { return @{ Status = 400; Body = @{ error = 'Drive is not safe to use.'; verdict = $v } } }
                $rp = [string]$Body.drive.RootPath
                if (-not $rp) { $rp = [string]$Body.drive.DriveLetter }
                if (-not (Test-Path -LiteralPath $rp)) { return @{ Status = 400; Body = @{ error = "Target root not found: $rp" } } }
                $State.Root = (Resolve-Path -LiteralPath $rp).Path
                $State.IsTestMode = $false; $State.TargetReady = $true
                return @{ Status = 200; Body = @{ root = $State.Root; isTestMode = $false; ready = $true; verdict = $v } }
            }
            '^GET /api/drives$' {
                $drives = if ($State.DriveProvider) {
                    Get-PocketRemovableDrive -DataProvider $State.DriveProvider -IncludeFixed:([bool]$State.IncludeFixed)
                } else {
                    Get-PocketRemovableDrive -IncludeFixed:([bool]$State.IncludeFixed)
                }
                return @{ Status = 200; Body = @{ drives = @($drives) } }
            }
            '^POST /api/safety$' {
                if (-not $Body.drive) { return @{ Status = 400; Body = @{ error = 'Missing drive.' } } }
                $v = Test-PocketDriveSafety -Drive $Body.drive -AllowAdvancedOverride:([bool]$Body.allowOverride)
                return @{ Status = 200; Body = $v }
            }
            '^POST /api/filesystem$' {
                $v = Test-PocketFilesystem -FileSystem ([string]$Body.fileSystem)
                return @{ Status = 200; Body = $v }
            }
            '^GET /api/empty$' {
                return @{ Status = 200; Body = (Test-PocketCardEmpty -Root $State.Root) }
            }
            '^GET /api/firmware$' {
                $m = Get-PocketFirmwareManifest -Path $State.FirmwareManifest
                $r = Resolve-PocketFirmwareRelease -Manifest $m
                return @{ Status = 200; Body = @{ latest = $m.latest; release = $r } }
            }
            '^POST /api/firmware/install$' {
                $m = Get-PocketFirmwareManifest -Path $State.FirmwareManifest
                $r = Resolve-PocketFirmwareRelease -Manifest $m -Version ([string]$Body.version)
                if ([string]$Body.mode -eq 'offline') {
                    if (-not $Body.localFile) { return @{ Status = 400; Body = @{ error = 'Offline mode needs localFile.' } } }
                    $res = Install-PocketFirmware -Root $State.Root -LocalFile ([string]$Body.localFile) -OfflineRelease $r -DryRun:([bool]$State.DryRun)
                } else {
                    $res = Install-PocketFirmware -Root $State.Root -Release $r -DryRun:([bool]$State.DryRun)
                }
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/folders$' {
                return @{ Status = 200; Body = (New-PocketFolderStructure -Root $State.Root -DryRun:([bool]$State.DryRun)) }
            }
            '^GET /api/systems$' {
                return @{ Status = 200; Body = @{ systems = @(Get-PocketSystem -Path $State.SystemsManifest) } }
            }
            '^POST /api/rom/plan$' {
                $sys = Get-PocketSystem -Path $State.SystemsManifest -Id ([string]$Body.systemId)
                $plan = New-PocketRomCopyPlan -System $sys -SourceFolder ([string]$Body.sourceFolder) -Root $State.Root `
                    -Recurse:([bool]$Body.recurse) -PreserveStructure:([bool]$Body.preserveStructure)
                return @{ Status = 200; Body = $plan }
            }
            '^POST /api/rom/copy$' {
                $sys = Get-PocketSystem -Path $State.SystemsManifest -Id ([string]$Body.systemId)
                $plan = New-PocketRomCopyPlan -System $sys -SourceFolder ([string]$Body.sourceFolder) -Root $State.Root `
                    -Recurse:([bool]$Body.recurse) -PreserveStructure:([bool]$Body.preserveStructure)
                $res = Invoke-PocketRomCopyPlan -Plan $plan -DryRun:([bool]$State.DryRun) -Overwrite:([bool]$Body.overwrite)
                return @{ Status = 200; Body = $res }
            }
            '^GET /api/installed-cores$' {
                return @{ Status = 200; Body = @{ cores = @(Get-PocketInstalledCore -Root $State.Root) } }
            }
            '^GET /api/cores$' {
                if (-not (Test-Path -LiteralPath $State.CoresManifest)) { return @{ Status = 200; Body = @{ cores = @() } } }
                $cores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $State.CoresManifest)
                return @{ Status = 200; Body = @{ cores = @($cores) } }
            }
            '^POST /api/cores/install$' {
                $core = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $State.CoresManifest) -Id ([string]$Body.coreId)
                if ([string]$Body.mode -eq 'offline') {
                    if (-not $Body.localZip) { return @{ Status = 400; Body = @{ error = 'Offline mode needs localZip.' } } }
                    $res = Install-PocketCore -Root $State.Root -LocalZip ([string]$Body.localZip) -Core $core -DryRun:([bool]$State.DryRun)
                } else {
                    $res = Install-PocketCore -Root $State.Root -Core $core -Download -DryRun:([bool]$State.DryRun)
                }
                return @{ Status = 200; Body = $res }
            }
            '^POST /api/summary$' {
                $res = New-PocketInstallSummary -Target $target -FirmwareResult $Body.firmware `
                    -FolderResult $Body.folder -RomResults @($Body.roms) -CoreResults @($Body.cores)
                return @{ Status = 200; Body = @{ text = $res.Text; totalRomsCopied = $res.TotalRomsCopied } }
            }
            default {
                return @{ Status = 404; Body = @{ error = "No route for $key" } }
            }
        }
    } catch {
        return @{ Status = 400; Body = @{ error = "$($_.Exception.Message)" } }
    }
}
