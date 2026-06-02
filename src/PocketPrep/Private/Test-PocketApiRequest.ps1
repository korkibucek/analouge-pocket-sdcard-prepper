# Pure request-authorisation check for the local API. Because the API can copy files
# and install firmware/cores, it must only be callable by our own page on this machine.
# Defends against other local apps, CSRF, and DNS-rebinding.

function Test-PocketApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $Headers,   # case-insensitive-ish header map
        [Parameter(Mandatory)] [string]    $ExpectedToken,
        [Parameter(Mandatory)] [int]       $Port
    )

    # Normalise header lookup (HTTP headers are case-insensitive).
    $h = @{}
    foreach ($k in $Headers.Keys) { $h[$k.ToLowerInvariant()] = $Headers[$k] }

    $token = [string]$h['x-pocketprep-token']
    if ($token -ne $ExpectedToken -or [string]::IsNullOrEmpty($ExpectedToken)) {
        return [pscustomobject]@{ Allowed = $false; Status = 401; Reason = 'Missing or invalid session token.' }
    }

    # Host header must be loopback (+ optional port).
    $allowedAuthorities = @("127.0.0.1:$Port", "localhost:$Port", "127.0.0.1", "localhost")
    $hostHeader = ([string]$h['host']).ToLowerInvariant()
    if ($hostHeader -and ($allowedAuthorities -notcontains $hostHeader)) {
        return [pscustomobject]@{ Allowed = $false; Status = 403; Reason = "Unexpected Host header '$hostHeader'." }
    }

    # If an Origin is present it must be our loopback origin (browsers send it on POST).
    $origin = ([string]$h['origin']).ToLowerInvariant()
    if ($origin) {
        $allowedOrigins = @("http://127.0.0.1:$Port", "http://localhost:$Port")
        if ($allowedOrigins -notcontains $origin) {
            return [pscustomobject]@{ Allowed = $false; Status = 403; Reason = "Cross-origin request rejected ('$origin')." }
        }
    }

    return [pscustomobject]@{ Allowed = $true; Status = 200; Reason = 'ok' }
}
