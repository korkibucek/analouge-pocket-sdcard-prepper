function Install-PocketBiosFile {
<#
.SYNOPSIS
    Places a user-supplied BIOS/required file into the exact slot a core declares.

.DESCRIPTION
    Cores that need a BIOS declare it in their data.json (required slot with a fixed
    filename); some systems also declare biosFiles in the systems manifest. This copies a
    file the USER ALREADY OWNS into that declared slot - renamed to the exact expected
    filename (cores match by name, and users' copies are often named differently) and
    size-verified after the copy.

    The target (PlatformId + FileName) must match a requirement declared by an installed
    core or a biosRequired system in the manifest - anything else is rejected, so this path
    can only ever fill genuinely required slots. The tool NEVER downloads BIOS files; this
    only places a local file the user supplies. Existing files are not overwritten unless
    -Overwrite. Supports -DryRun.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER PlatformId
    The platform whose requirement is being satisfied (e.g. 'ng').

.PARAMETER FileName
    The declared required filename (e.g. 'neogeo.zip', 'uni-bios_4_0.rom').

.PARAMETER SourceFile
    Path to the BIOS file the user owns. It is copied (and renamed to FileName).

.PARAMETER SystemsManifest
    Optional path to manifests/systems.json, so manifest-declared BIOS (e.g. Neo Geo's
    neogeo.zip) can be installed even before the core itself is on the card.

.PARAMETER Overwrite
    Replace an existing file at the destination.

.PARAMETER DryRun
    Validate and report without copying.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Used inside the $log closure scriptblock, which the analyzer does not trace.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Copies one user-supplied file into a declared slot; -DryRun previews.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $PlatformId,

        [Parameter(Mandatory, Position = 2)]
        [string] $FileName,

        [Parameter(Mandatory, Position = 3)]
        [string] $SourceFile,

        [string] $SystemsManifest,

        [switch] $Overwrite,

        [switch] $DryRun,

        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    if (-not (Test-Path -LiteralPath $SourceFile -PathType Leaf)) {
        throw "BIOS source file not found: $SourceFile"
    }

    # Build the set of DECLARED requirements; only these may be targeted.
    $requirements = [System.Collections.Generic.List[object]]::new()
    foreach ($core in @(Get-PocketCoreRequiredFile -Root $Root)) {
        foreach ($req in @($core.Required)) {
            $requirements.Add([pscustomobject]@{
                PlatformId = $core.PlatformId; Filename = $req.Filename
                Destination = $req.Location; DeclaredBy = "core '$($core.Identifier)'"
            })
        }
    }
    if ($SystemsManifest -and (Test-Path -LiteralPath $SystemsManifest -PathType Leaf)) {
        foreach ($b in @(Get-PocketBiosStatus -Root $Root -SystemsManifest $SystemsManifest)) {
            foreach ($name in @($b.Required)) {
                $requirements.Add([pscustomobject]@{
                    PlatformId = $b.PlatformId; Filename = $name
                    Destination = (Join-Path $b.Location $name); DeclaredBy = "system '$($b.SystemId)'"
                })
            }
        }
    }

    $match = $requirements | Where-Object {
        $_.PlatformId -ieq $PlatformId -and $_.Filename -ieq $FileName
    } | Select-Object -First 1
    if (-not $match) {
        throw "'$FileName' on platform '$PlatformId' is not a BIOS/required file declared by any installed core or biosRequired system - refusing to place it. (Use the ROM uploader for game files.)"
    }

    $dest = $match.Destination
    $renamed = ((Split-Path -Leaf $SourceFile) -ne $match.Filename)

    if ((Test-Path -LiteralPath $dest -PathType Leaf) -and -not $Overwrite) {
        & $log "BIOS $($match.Filename) already present at $dest (no -Overwrite); not replaced" 'WARN'
        return [pscustomobject]@{
            PSTypeName = 'PocketPrep.BiosInstallResult'
            PlatformId = $PlatformId; FileName = $match.Filename; Destination = $dest
            DeclaredBy = $match.DeclaredBy; Installed = $false; Renamed = $renamed; DryRun = [bool]$DryRun
            Message    = 'A file already exists at the destination; enable overwrite to replace it.'
        }
    }

    if (-not $DryRun) {
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        Copy-Item -LiteralPath $SourceFile -Destination $dest -Force:$Overwrite
        $srcLen = (Get-Item -LiteralPath $SourceFile).Length
        $dstLen = (Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue).Length
        if ($dstLen -ne $srcLen) { throw "size mismatch after copy (expected $srcLen bytes, got $dstLen)" }
        & $log "BIOS placed: $($match.Filename) -> $dest (declared by $($match.DeclaredBy))$(if ($renamed) { ' [renamed from ' + (Split-Path -Leaf $SourceFile) + ']' })" 'INFO'
    } else {
        & $log "DRYRUN BIOS: would place $($match.Filename) -> $dest" 'INFO'
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.BiosInstallResult'
        PlatformId = $PlatformId; FileName = $match.Filename; Destination = $dest
        DeclaredBy = $match.DeclaredBy; Installed = (-not $DryRun); Renamed = $renamed; DryRun = [bool]$DryRun
        Message    = ''
    }
}
