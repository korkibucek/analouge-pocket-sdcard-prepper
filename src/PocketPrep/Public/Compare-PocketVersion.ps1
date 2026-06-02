function Compare-PocketVersion {
<#
.SYNOPSIS
    Compares two core version strings and reports whether an update is available.

.DESCRIPTION
    Pure comparison. Strips a leading 'v', compares dotted numeric components
    (e.g. 1.10.0 > 1.9.0). Falls back to a case-insensitive string compare when the
    versions are not purely numeric.

.PARAMETER Installed
    The currently installed version.

.PARAMETER Latest
    The latest available version.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Installed,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Latest
    )

    $clean = { param($v) ($v ?? '').Trim().TrimStart('v', 'V') }
    $i = & $clean $Installed
    $l = & $clean $Latest

    $numeric = { param($v) $v -match '^\d+(\.\d+)*$' }
    $cmp = $null
    if ((& $numeric $i) -and (& $numeric $l)) {
        $ia = $i.Split('.') | ForEach-Object { [int]$_ }
        $la = $l.Split('.') | ForEach-Object { [int]$_ }
        $n = [Math]::Max($ia.Count, $la.Count)
        $cmp = 0
        for ($k = 0; $k -lt $n; $k++) {
            $a = if ($k -lt $ia.Count) { $ia[$k] } else { 0 }
            $b = if ($k -lt $la.Count) { $la[$k] } else { 0 }
            if ($a -ne $b) { $cmp = $a - $b; break }
        }
    } else {
        $cmp = [string]::Compare($i, $l, [System.StringComparison]::OrdinalIgnoreCase)
    }

    [pscustomobject]@{
        PSTypeName       = 'PocketPrep.VersionComparison'
        Installed        = $Installed
        Latest           = $Latest
        UpdateAvailable  = ($cmp -lt 0)
        Same             = ($cmp -eq 0)
        InstalledNewer   = ($cmp -gt 0)
    }
}
