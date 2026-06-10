# Resolves a GitHub release for a core repo. Shared by the core installer (needs the
# zip asset URL) and the update checker (needs the version tag). Restricts downloads to
# GitHub hosts. Network-bound; not exercised in CI.

function Get-PocketLatestRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Owner,
        [Parameter(Mandatory)] [string] $Repo,
        [string] $Tag,
        # Optional regex to select a specific .zip asset when a release ships several
        # (e.g. opengateware arcade repos ship *_pocket-*.zip AND *_rom-recipes-*.zip).
        # Default: the first .zip asset, as before.
        [string] $AssetPattern
    )

    $allowedHosts = @('github.com', 'objects.githubusercontent.com',
                      'release-assets.githubusercontent.com', 'api.github.com', 'codeload.github.com')

    $relUrl = if ($Tag) {
        "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag"
    } else {
        "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    }

    $headers = @{ 'User-Agent' = 'PocketPrep' }
    # An optional token raises the GitHub API rate limit from 60 to 5000 requests/hour.
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }

    try {
        $rel = Invoke-PocketRest -Uri $relUrl -Headers $headers
    } catch {
        $msg = "$($_.Exception.Message)"
        if ($msg -match '\b403\b|rate limit') {
            throw "GitHub API rate limit reached while resolving $Owner/$Repo. Wait an hour, or set the GITHUB_TOKEN environment variable to raise the limit. ($msg)"
        }
        if ($msg -match '\b404\b|Not Found') {
            throw "GitHub release not found for $Owner/$Repo$(if ($Tag) { " tag '$Tag'" }). ($msg)"
        }
        throw "Could not reach GitHub to resolve $Owner/$Repo release (offline or network error?): $msg"
    }
    $zips = @($rel.assets | Where-Object { $_.name -match '\.zip$' })
    $asset = if ($AssetPattern) { $zips | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1 }
             else { $zips | Select-Object -First 1 }
    $zipUrl = $null
    if ($asset) {
        $dlHost = ([Uri]$asset.browser_download_url).Host
        if ($allowedHosts -notcontains $dlHost) {
            throw "Refusing to use core asset from non-GitHub host '$dlHost'."
        }
        $zipUrl = $asset.browser_download_url
    }

    [pscustomobject]@{
        Version  = [string]$rel.tag_name
        ZipUrl   = $zipUrl
        ZipName  = if ($asset) { [string]$asset.name } else { $null }
    }
}
