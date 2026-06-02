function New-PocketFolderStructure {
<#
.SYNOPSIS
    Creates the openFPGA top-level folder structure on the SD root.

.DESCRIPTION
    Creates the verified top-level folders (Assets, Cores, Saves, Settings, System,
    Memories, Presets, "GB Studio", Platforms). Idempotent: existing folders are
    left untouched and never deleted. Supports -DryRun to preview actions.

    Source for the folder set:
    https://www.analogue.co/developer/docs/directories-and-sd-folder-structure

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER DryRun
    Report what would be created without creating anything.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [switch] $DryRun
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "SD root path not found or not a folder: $Root"
    }

    $created  = [System.Collections.Generic.List[string]]::new()
    $existing = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $script:PocketDefaults.FolderStructure) {
        $target = Join-Path $Root $name
        if (Test-Path -LiteralPath $target -PathType Container) {
            $existing.Add($name)
        } else {
            $created.Add($name)
            if (-not $DryRun) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }
        }
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.FolderResult'
        Root       = (Resolve-Path -LiteralPath $Root).Path
        DryRun     = [bool]$DryRun
        Created    = $created.ToArray()
        Existing   = $existing.ToArray()
    }
}
