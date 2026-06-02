# Resolves a GitHub release for a core repo. Shared by the core installer (needs the
# zip asset URL) and the update checker (needs the version tag). Restricts downloads to
# GitHub hosts. Network-bound; not exercised in CI.

function Get-PocketLatestRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Owner,
        [Parameter(Mandatory)] [string] $Repo,
        [string] $Tag
    )

    $allowedHosts = @('github.com', 'objects.githubusercontent.com',
                      'release-assets.githubusercontent.com', 'api.github.com', 'codeload.github.com')

    $relUrl = if ($Tag) {
        "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag"
    } else {
        "https://api.github.com/repos/$Owner/$Repo/releases/latest"
    }

    $rel = Invoke-RestMethod -Uri $relUrl -Headers @{ 'User-Agent' = 'PocketPrep' } -ErrorAction Stop
    $asset = $rel.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
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
