function Get-PocketBiosStatus {
<#
.SYNOPSIS
    Reports whether the BIOS files required by BIOS-dependent systems are present on a card.

.DESCRIPTION
    Some systems (notably Neo Geo) need a copyrighted system BIOS that this tool will NEVER
    download or supply - the user must place a BIOS they legally own. This is a read-only
    check: for every system in the manifest with biosRequired = true, it reports which of the
    declared biosFiles are present under Assets/<platformId>/common and which are missing, so
    the UI can guide the user to add the BIOS themselves.

    Nothing is downloaded, copied, or deleted.

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER SystemsManifest
    Path to manifests/systems.json.

.PARAMETER SystemId
    Optionally restrict the check to one system id (e.g. 'neogeo').
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [Parameter(Mandatory, Position = 1)]
        [string] $SystemsManifest,

        [string] $SystemId
    )

    $systems = @(Get-PocketSystem -Path $SystemsManifest) | Where-Object { $_.BiosRequired }
    if ($SystemId) { $systems = @($systems | Where-Object { $_.Id -eq $SystemId }) }

    $result = foreach ($sys in $systems) {
        $common = Join-Path (Join-Path (Join-Path $Root 'Assets') $sys.PlatformId) 'common'
        $present = [System.Collections.Generic.List[string]]::new()
        $missing = [System.Collections.Generic.List[string]]::new()
        foreach ($bf in @($sys.BiosFiles)) {
            $hit = $false
            if (Test-Path -LiteralPath $common -PathType Container) {
                # Match by leaf name, case-insensitively, anywhere under common.
                $hit = [bool](Get-ChildItem -LiteralPath $common -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ieq $bf } | Select-Object -First 1)
            }
            if ($hit) { $present.Add($bf) } else { $missing.Add($bf) }
        }
        [pscustomobject]@{
            PSTypeName   = 'PocketPrep.BiosStatus'
            SystemId     = $sys.Id
            DisplayName  = $sys.DisplayName
            PlatformId   = $sys.PlatformId
            Location     = $common
            Required     = @($sys.BiosFiles)
            Present      = $present.ToArray()
            Missing      = $missing.ToArray()
            Satisfied    = ($missing.Count -eq 0)
        }
    }
    return @($result)
}
