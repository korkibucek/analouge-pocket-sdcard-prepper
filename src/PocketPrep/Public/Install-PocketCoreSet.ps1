function Install-PocketCoreSet {
<#
.SYNOPSIS
    Installs many openFPGA cores from the manifest in one operation (e.g. the whole inventory).

.DESCRIPTION
    Downloads and installs each requested core via Install-PocketCore, continuing past
    individual failures and returning a per-core result. Stops early and reports clearly if
    GitHub rate-limits the run (remaining cores are marked skipped). Supports -DryRun (lists
    what would be installed without any network or writes).

    This is a large download (dozens of repositories). Set the GITHUB_TOKEN environment
    variable to avoid the unauthenticated GitHub API rate limit (60 requests/hour).

.PARAMETER Root
    SD card root or fake SD root folder.

.PARAMETER CoresManifest
    Path to cores.json.

.PARAMETER Id
    Optional subset of core ids to install (default: all in the manifest).

.PARAMETER DryRun
    Report what would be installed without downloading or writing.

.PARAMETER Logger
    Optional logger from New-PocketLogger.
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Logger',
        Justification = 'Forwarded to Install-PocketCore.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $CoresManifest,
        [string[]] $Id,
        [switch] $DryRun,
        [psobject] $Logger
    )

    $log = { param($m, $lvl = 'INFO') if ($Logger) { Write-PocketLog -Logger $Logger -Message $m -Level $lvl | Out-Null } }

    $allCores = Resolve-PocketCore -Manifest (Get-PocketCoreManifest -Path $CoresManifest)
    $selected = if ($Id) { @($allCores | Where-Object { $Id -contains $_.Id }) } else { @($allCores) }

    # Install each unique GitHub repo once: a repo's release zip ships ALL the cores it
    # provides, so several inventory entries that share a repo (e.g. GB + GBC) are one
    # download. We don't require a specific Cores/<identifier>/ folder for the bulk path
    # (folder names don't always match the inventory identifier).
    $cores = @($selected | Group-Object { ($_.Owner + '/' + $_.Repo).ToLowerInvariant() } |
        ForEach-Object { $_.Group | Select-Object -First 1 })

    $results = [System.Collections.Generic.List[object]]::new()
    $rateLimited = $false

    foreach ($core in $cores) {
        if ($rateLimited) {
            $results.Add([pscustomobject]@{ PSTypeName='PocketPrep.CoreSetItem'; Identifier=$core.Identifier
                Status='skipped'; PlacedCount=0; Version=$null; Error='skipped (GitHub rate limit reached earlier)' })
            continue
        }
        if ($DryRun) {
            $results.Add([pscustomobject]@{ PSTypeName='PocketPrep.CoreSetItem'; Identifier=$core.Identifier
                Status='would-install'; PlacedCount=0; Version=$null; Error=$null })
            continue
        }
        try {
            $r = Install-PocketCore -Root $Root -Core $core -Download -Overwrite -SkipIdentifierCheck -Logger $Logger
            $results.Add([pscustomobject]@{ PSTypeName='PocketPrep.CoreSetItem'; Identifier=$core.Identifier
                Status='installed'; PlacedCount=$r.PlacedCount; Version=$r.Version; Error=$null })
            & $log "Core set: installed $($core.Identifier) ($($r.PlacedCount) files)" 'INFO'
        } catch {
            $msg = "$($_.Exception.Message)"
            if ($msg -match 'rate limit') { $rateLimited = $true }
            $results.Add([pscustomobject]@{ PSTypeName='PocketPrep.CoreSetItem'; Identifier=$core.Identifier
                Status='failed'; PlacedCount=0; Version=$null; Error=$msg })
            & $log "Core set: FAILED $($core.Identifier): $msg" 'WARN'
        }
    }

    $arr = $results.ToArray()
    [pscustomobject]@{
        PSTypeName     = 'PocketPrep.CoreSetResult'
        Requested      = $cores.Count
        InstalledCount = @($arr | Where-Object Status -eq 'installed').Count
        FailedCount    = @($arr | Where-Object Status -eq 'failed').Count
        SkippedCount   = @($arr | Where-Object Status -eq 'skipped').Count
        RateLimited    = $rateLimited
        DryRun         = [bool]$DryRun
        Results        = $arr
    }
}
