function Repair-PocketCore {
<#
.SYNOPSIS
    Re-downloads and reinstalls a core's own files to fix a partial/corrupt install.

.DESCRIPTION
    Reinstalls a core via the normal download path with -Overwrite, refreshing only the
    openFPGA core folders (Assets/Cores/Platforms/Presets/Settings). The user's ROMs under
    Assets/<platformId>/common and their Saves/Memories are NOT touched - core zips never
    contain user ROMs, and the installer never extracts Saves/Memories. Supports -DryRun.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER Id
    The core id (manifest id) to repair.

.PARAMETER CoresManifest
    Path to manifests/cores.json (to resolve the core's repository).

.PARAMETER Tag
    Optional specific release tag; defaults to the latest release.

.PARAMETER DryRun
    Plan only; do not download or extract.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $Id,

        [Parameter(Mandatory, Position = 2)]
        [string] $CoresManifest,

        [string] $Tag,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $core = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest) -Id $Id
    if (-not $core) { throw "Core id '$Id' not found in the manifest." }

    $params = @{
        Root = $Root; Core = $core; Download = $true; Overwrite = $true
        SkipIdentifierCheck = $true; DryRun = $DryRun; Logger = $Logger
    }
    if ($Tag) { $params.Tag = $Tag }
    $res = Install-PocketCore @params
    $res | Add-Member -NotePropertyName Repaired -NotePropertyValue (-not $DryRun) -Force
    return $res
}
