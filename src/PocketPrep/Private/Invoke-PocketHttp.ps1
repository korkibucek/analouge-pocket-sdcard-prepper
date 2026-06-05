# Shared, robust HTTP helpers used by firmware/core download + GitHub release lookup.
# Adds explicit timeouts, bounded retry with backoff on TRANSIENT failures (timeouts,
# connection errors, HTTP 5xx, 429), and clear errors. Non-transient failures (e.g. 404,
# 403) fail fast. The actual request senders are injectable so the retry logic is
# unit-testable without network access.

function Test-PocketTransientError {
    # Returns $true if the given ErrorRecord/exception looks worth retrying.
    [CmdletBinding()]
    param([Parameter(Mandatory)] $ErrorObject)

    $ex = if ($ErrorObject -is [System.Management.Automation.ErrorRecord]) { $ErrorObject.Exception } else { $ErrorObject }

    # HTTP status responses (PS7 throws HttpResponseException with a Response.StatusCode).
    $status = $null
    $resp = $ex.PSObject.Properties['Response']
    if ($resp -and $ex.Response) {
        try { $status = [int]$ex.Response.StatusCode } catch { $status = $null }
    }
    if ($status) {
        return ($status -ge 500 -or $status -eq 429 -or $status -eq 408)
    }

    # Connection/timeout style exceptions have no HTTP status; treat as transient.
    $typeName = $ex.GetType().FullName
    foreach ($t in 'System.Net.Http.HttpRequestException',
                   'System.Threading.Tasks.TaskCanceledException',
                   'System.OperationCanceledException',
                   'System.Net.WebException',
                   'System.Net.Sockets.SocketException',
                   'System.IO.IOException') {
        if ($typeName -eq $t) { return $true }
    }
    # Message-based fallback for timeouts surfaced as generic exceptions.
    if ("$($ex.Message)" -match 'timed out|timeout|connection|reset by peer|temporarily') { return $true }
    return $false
}

function Invoke-PocketWithRetry {
    # Runs $Action, retrying on transient errors up to $MaxRetries extra attempts.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock] $Action,
        [string] $OperationName = 'request',
        [int] $MaxRetries = 3,
        [double] $BaseDelaySeconds = 1.0,
        [scriptblock] $OnRetry
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            return & $Action
        } catch {
            $isTransient = Test-PocketTransientError -ErrorObject $_
            if (-not $isTransient -or $attempt -gt $MaxRetries) {
                if ($attempt -gt 1) {
                    throw "Failed $OperationName after $attempt attempt(s): $($_.Exception.Message)"
                }
                throw
            }
            $delay = [Math]::Min($BaseDelaySeconds * [Math]::Pow(2, $attempt - 1), 30)
            if ($OnRetry) { & $OnRetry $attempt $delay $_ }
            Start-Sleep -Seconds $delay
        }
    }
}

function Invoke-PocketRest {
    # GET JSON with timeout + retry. $RequestSender is injectable for testing.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '',
        Justification = 'Headers/TimeoutSec are passed to $RequestSender inside the retry closure, which the analyzer does not trace.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [hashtable] $Headers = @{ 'User-Agent' = 'PocketPrep' },
        [int] $TimeoutSec = 30,
        [int] $MaxRetries = 3,
        [scriptblock] $RequestSender,
        [scriptblock] $OnRetry
    )
    if (-not $RequestSender) {
        $RequestSender = { param($u, $h, $t) Invoke-RestMethod -Uri $u -Headers $h -TimeoutSec $t -ErrorAction Stop }
    }
    return Invoke-PocketWithRetry -OperationName "GET $Uri" -MaxRetries $MaxRetries -OnRetry $OnRetry -Action {
        & $RequestSender $Uri $Headers $TimeoutSec
    }
}

function Invoke-PocketDownload {
    # Download to a file with timeout + retry, and a best-effort size sanity check.
    # $RequestSender is injectable for testing.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'TimeoutSec',
        Justification = 'Passed to $RequestSender inside the retry closure, which the analyzer does not trace.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $OutFile,
        [int] $TimeoutSec = 300,
        [int] $MaxRetries = 3,
        [int64] $MaxBytes = 0,        # hard cap; 0 = no cap
        [int64] $ExpectedBytes = 0,   # used for a sanity ratio if MaxBytes not set
        [scriptblock] $RequestSender,
        [scriptblock] $OnRetry
    )
    if (-not $RequestSender) {
        $RequestSender = { param($u, $o, $t) Invoke-WebRequest -Uri $u -OutFile $o -TimeoutSec $t -MaximumRedirection 5 -ErrorAction Stop }
    }

    Invoke-PocketWithRetry -OperationName "download $Uri" -MaxRetries $MaxRetries -OnRetry $OnRetry -Action {
        if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue }
        & $RequestSender $Uri $OutFile $TimeoutSec
    } | Out-Null

    if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf)) {
        throw "Download of $Uri produced no file."
    }
    $size = (Get-Item -LiteralPath $OutFile).Length

    # Size guard. If a hard cap is set, enforce it. Otherwise, if we know the expected
    # size, flag a wildly-larger result (likely a redirect to the wrong thing).
    $cap = $MaxBytes
    if ($cap -le 0 -and $ExpectedBytes -gt 0) { $cap = [int64]([Math]::Max($ExpectedBytes * 4, $ExpectedBytes + 50MB)) }
    if ($cap -gt 0 -and $size -gt $cap) {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        throw "Downloaded file from $Uri is ${size} bytes, larger than the allowed ${cap} bytes; refusing."
    }
    return $size
}
