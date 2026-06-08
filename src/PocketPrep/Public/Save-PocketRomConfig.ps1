function Save-PocketRomConfig {
<#
.SYNOPSIS
    Writes the ROM source mapping to a card (or fake SD root).

.DESCRIPTION
    Persists the user's source-folder -> system mappings to pocketprep/rom-sources.json
    so a later run can rescan for new ROMs (Invoke-PocketRomRescan) without re-running the
    wizard. Each source needs a non-empty SystemId and Path; rows are de-duplicated by
    SystemId+Path (case-insensitive). The file contains only paths and options - never any
    ROM data.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER Sources
    Array of source descriptors, each with SystemId, Path and optional Recurse. Accepts
    objects with those properties or hashtables with those keys (or the lower-case JSON
    forms systemId/path/recurse).

.PARAMETER DryRun
    Validate and report without writing the file.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Non-destructive single-file write; -DryRun provides the preview path.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyCollection()]
        [psobject[]] $Sources,

        [switch] $DryRun
    )

    $prop = { param($o, $a, $b) if ($o.PSObject.Properties[$a]) { $o.$a } else { $o.$b } }

    $seen = @{}
    $clean = foreach ($s in $Sources) {
        $sysId = [string](& $prop $s 'SystemId' 'systemId')
        $path  = [string](& $prop $s 'Path' 'path')
        $rec   = [bool](& $prop $s 'Recurse' 'recurse')
        if ([string]::IsNullOrWhiteSpace($sysId) -or [string]::IsNullOrWhiteSpace($path)) {
            throw "Each ROM source needs a non-empty systemId and path."
        }
        $key = ($sysId + '|' + $path).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [pscustomobject]@{ systemId = $sysId; path = $path; recurse = $rec }
    }
    $clean = @($clean)

    $dir  = Join-Path $Root 'pocketprep'
    $path = Join-Path $dir 'rom-sources.json'
    $config = [pscustomobject]@{ version = 1; sources = $clean }

    if (-not $DryRun) {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding utf8
    }

    [pscustomobject]@{
        PSTypeName  = 'PocketPrep.RomConfigSaveResult'
        Path        = $path
        SourceCount = $clean.Count
        DryRun      = [bool]$DryRun
        Written     = (-not $DryRun)
    }
}
