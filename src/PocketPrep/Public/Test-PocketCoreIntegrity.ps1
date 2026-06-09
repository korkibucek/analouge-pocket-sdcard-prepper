function Test-PocketCoreIntegrity {
<#
.SYNOPSIS
    Flags installed cores that are missing their required openFPGA definition files.

.DESCRIPTION
    A partial or corrupted core install often shows up as a Cores/<identifier>/ folder that is
    missing one of the core definition files openFPGA requires. This reads each installed core
    folder and reports which of the required files are present/missing, plus whether core.json
    still parses. Read-only - it never downloads or changes anything (use Repair-PocketCore to
    fix a flagged core).

    Required set: core.json, data.json, video.json, input.json (the always-present openFPGA
    definition files); audio.json and interact.json are checked but only reported, not treated
    as fatal, since a few cores legitimately omit them.

.PARAMETER Root
    SD card root or fake SD root folder.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root
    )

    $required = @('core.json', 'data.json', 'video.json', 'input.json')
    $optional = @('audio.json', 'interact.json')

    $result = foreach ($core in @(Get-PocketInstalledCore -Root $Root)) {
        $present = [System.Collections.Generic.List[string]]::new()
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $required) {
            if (Test-Path -LiteralPath (Join-Path $core.Path $f) -PathType Leaf) { $present.Add($f) } else { $missing.Add($f) }
        }
        $optionalMissing = @($optional | Where-Object { -not (Test-Path -LiteralPath (Join-Path $core.Path $_) -PathType Leaf) })

        # core.json must parse for the core to load.
        $coreJsonOk = $true
        $cj = Join-Path $core.Path 'core.json'
        if (Test-Path -LiteralPath $cj -PathType Leaf) {
            try { Get-Content -LiteralPath $cj -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null } catch { $coreJsonOk = $false }
        } else { $coreJsonOk = $false }

        [pscustomobject]@{
            PSTypeName      = 'PocketPrep.CoreIntegrity'
            Identifier      = $core.Identifier
            Ok              = ($missing.Count -eq 0 -and $coreJsonOk)
            CoreJsonValid   = $coreJsonOk
            Present         = $present.ToArray()
            Missing         = $missing.ToArray()
            OptionalMissing = @($optionalMissing)
        }
    }
    return @($result)
}
