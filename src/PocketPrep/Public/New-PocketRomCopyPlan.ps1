function New-PocketRomCopyPlan {
<#
.SYNOPSIS
    Builds (but does not execute) a plan to copy a system's ROMs to the SD card.

.DESCRIPTION
    Pure planning function. Given a system object and a source folder, it matches
    files by the system's supported extensions and computes destination paths under
    Assets/<platformId>/common. Nothing is copied here - call Invoke-PocketRomCopyPlan.

    This tool copies USER-PROVIDED ROMs only. It never downloads or supplies ROMs,
    and it does not copy BIOS files unless you explicitly opt in elsewhere.

.PARAMETER System
    A system object from Get-PocketSystem.

.PARAMETER SourceFolder
    Folder containing the user's ROM files.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PreserveStructure
    Keep subfolder layout under the destination. Default is to flatten, which is
    what most cores expect.

.PARAMETER Recurse
    Search subfolders of SourceFolder for ROMs.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject] $System,

        [Parameter(Mandatory)]
        [string] $SourceFolder,

        [Parameter(Mandatory)]
        [string] $Root,

        [switch] $PreserveStructure,

        [switch] $Recurse
    )

    if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
        throw "Source ROM folder not found: $SourceFolder"
    }

    $destRoot = Join-Path (Join-Path (Join-Path $Root 'Assets') $System.PlatformId) 'common'
    $exts = $System.SupportedExtensions

    $allFiles = Get-ChildItem -LiteralPath $SourceFolder -File -Recurse:$Recurse -ErrorAction SilentlyContinue
    $matched  = $allFiles | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() }

    $sourceFull = (Resolve-Path -LiteralPath $SourceFolder).Path

    $items = foreach ($f in $matched) {
        if ($PreserveStructure -and $Recurse) {
            $rel = $f.FullName.Substring($sourceFull.Length).TrimStart([char]'\', [char]'/')
            $dest = Join-Path $destRoot $rel
        } else {
            $rel = $f.Name
            $dest = Join-Path $destRoot $f.Name
        }
        [pscustomobject]@{
            Source       = $f.FullName
            Destination  = $dest
            RelativePath = $rel
            SizeBytes    = $f.Length
        }
    }
    $items = @($items)

    [pscustomobject]@{
        PSTypeName         = 'PocketPrep.RomCopyPlan'
        SystemId           = $System.Id
        SystemDisplayName  = $System.DisplayName
        PlatformId         = $System.PlatformId
        SourceFolder       = $sourceFull
        Destination        = $destRoot
        Flatten            = (-not $PreserveStructure)
        FileCount          = $items.Count
        TotalBytes         = (($items | Measure-Object -Property SizeBytes -Sum).Sum) ?? 0
        SkippedNonMatching = (@($allFiles).Count - $items.Count)
        Items              = $items
    }
}
