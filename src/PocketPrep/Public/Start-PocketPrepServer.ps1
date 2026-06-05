function Start-PocketPrepServer {
<#
.SYNOPSIS
    Runs the local web UI server for the Analogue Pocket SD Card Prepper.

.DESCRIPTION
    Serves a browser-based wizard and a JSON REST API over the PocketPrep engine. The
    server binds to 127.0.0.1 ONLY and requires a per-session token on every /api call,
    and validates Host/Origin headers. Because the API can copy files and install
    firmware/cores, these protections stop other local apps, web pages (CSRF), or
    DNS-rebinding attempts from driving it.

    Works on Windows, Linux, and macOS (PowerShell 7 + .NET HttpListener).

.PARAMETER Root
    SD card root / mountpoint, or a fake SD root in test mode.

.PARAMETER TestMode
    Treat Root as an ordinary folder (created if missing).

.PARAMETER Port
    TCP port on 127.0.0.1. 0 (default) picks a free port.

.PARAMETER DryRun
    Plan only; the API performs no writes.

.PARAMETER NoBrowser
    Do not auto-open the browser.

.PARAMETER FirmwareManifest / SystemsManifest / CoresManifest
    Manifest paths (default to the repo manifests).
#>
    [CmdletBinding()]
    param(
        [string] $Root,
        [switch] $TestMode,
        [int]    $Port = 0,
        [switch] $DryRun,
        [switch] $NoBrowser,
        [switch] $IncludeFixed,
        [string] $FirmwareManifest,
        [string] $SystemsManifest,
        [string] $CoresManifest,
        [scriptblock] $DriveProvider,
        # Auto-shutdown after this many seconds with no requests (0 = never). Closes a
        # forgotten local server holding a privileged endpoint open.
        [int] $IdleTimeoutSeconds = 3600,
        # Log each request (method, path, status) to the console for troubleshooting.
        [switch] $LogRequests
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot          # .../src/PocketPrep
    $repoRoot   = Split-Path -Parent (Split-Path -Parent $moduleRoot)
    $webRoot    = Join-Path $moduleRoot 'web'
    if (-not $FirmwareManifest) { $FirmwareManifest = Join-Path $repoRoot 'manifests/firmware.json' }
    if (-not $SystemsManifest)  { $SystemsManifest  = Join-Path $repoRoot 'manifests/systems.json' }
    if (-not $CoresManifest)    { $CoresManifest    = Join-Path $repoRoot 'manifests/cores.json' }

    if ($TestMode -and -not $Root) { $Root = Join-Path ([System.IO.Path]::GetTempPath()) 'PocketSDTest' }
    if ($TestMode -and -not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }
    # A target may be set now (via -Root/-TestMode) or chosen later in the browser.
    $targetReady = $false
    if ($Root) { $Root = (Resolve-Path -LiteralPath $Root).Path; $targetReady = $true }

    if ($Port -eq 0) {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $probe.Start(); $Port = $probe.LocalEndpoint.Port; $probe.Stop()
    }

    $token = [Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16))

    $state = @{
        Root = $Root; IsTestMode = [bool]$TestMode; DryRun = [bool]$DryRun; TargetReady = $targetReady
        FirmwareManifest = $FirmwareManifest; SystemsManifest = $SystemsManifest; CoresManifest = $CoresManifest
        IncludeFixed = [bool]$IncludeFixed; DriveProvider = $DriveProvider
    }

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()
    $url = "http://127.0.0.1:$Port/"

    Write-Host "Analogue Pocket SD Card Prepper - web UI" -ForegroundColor Green
    Write-Host "  URL:   $url" -ForegroundColor Cyan
    Write-Host "  Token: $token"
    Write-Host "  Root:  $(if($Root){$Root}else{'(choose in the browser)'})$(if($TestMode){' (TEST MODE)'})$(if($DryRun){' [DRY-RUN]'})"
    Write-Host "  (Press Ctrl+C to stop, or click Finish in the page.)"

    if (-not $NoBrowser) {
        # Open the bare URL: the served page already carries the session token (injected
        # into index.html), so we avoid leaking the token via the URL / shell history.
        try {
            if ($IsWindows)   { Start-Process $url | Out-Null }
            elseif ($IsMacOS) { & open $url }
            else              { & xdg-open $url 2>$null }
        } catch { Write-Host "  Open this URL in your browser: $url" -ForegroundColor Yellow }
    }

    $contentTypes = @{ '.html'='text/html; charset=utf-8'; '.js'='text/javascript'; '.css'='text/css'; '.json'='application/json' }

    try {
        $running = $true
        while ($running -and $listener.IsListening) {
            # Accept with an optional idle timeout so a forgotten server shuts itself down.
            $ctxTask = $listener.GetContextAsync()
            if ($IdleTimeoutSeconds -gt 0) {
                if (-not $ctxTask.Wait([timespan]::FromSeconds($IdleTimeoutSeconds))) {
                    Write-Host "Idle for ${IdleTimeoutSeconds}s with no requests - shutting down." -ForegroundColor Yellow
                    break
                }
            } else {
                $ctxTask.Wait()
            }
            $ctx = $ctxTask.Result
            $req = $ctx.Request
            $res = $ctx.Response
            try {
                $path = $req.Url.AbsolutePath
                if ($path -eq '/') { $path = '/index.html' }

                # Quietly answer favicon requests so browsers don't log 404 noise.
                if ($path -eq '/favicon.ico') { $res.StatusCode = 204; continue }

                if ($path -like '/api/*') {
                    # Authorise.
                    $headers = @{}
                    foreach ($k in $req.Headers.AllKeys) { $headers[$k] = $req.Headers[$k] }
                    $auth = Test-PocketApiRequest -Headers $headers -ExpectedToken $token -Port $Port
                    if (-not $auth.Allowed) {
                        Write-PocketServerJson $res $auth.Status @{ error = $auth.Reason }
                        continue
                    }
                    if ($path -eq '/api/shutdown') { Write-PocketServerJson $res 200 @{ ok = $true }; $running = $false; continue }

                    $bodyObj = $null
                    if ($req.HasEntityBody) {
                        $reader = [System.IO.StreamReader]::new($req.InputStream, $req.ContentEncoding)
                        $raw = $reader.ReadToEnd(); $reader.Dispose()
                        if ($raw.Trim()) { $bodyObj = $raw | ConvertFrom-Json }
                    }
                    $result = Invoke-PocketApiRoute -Method $req.HttpMethod -Path $path -Body $bodyObj -State $state
                    Write-PocketServerJson $res $result.Status $result.Body
                } else {
                    # Static file (whitelisted to the web folder).
                    $safe = ($path -replace '\.\.', '').TrimStart('/')
                    $file = Join-Path $webRoot $safe
                    if (Test-Path -LiteralPath $file -PathType Leaf) {
                        $text = Get-Content -LiteralPath $file -Raw
                        if ($safe -eq 'index.html') { $text = $text.Replace('__POCKETPREP_TOKEN__', $token) }
                        $ext = [System.IO.Path]::GetExtension($file)
                        $res.ContentType = $contentTypes[$ext] ?? 'application/octet-stream'
                        $buf = [System.Text.Encoding]::UTF8.GetBytes($text)
                        $res.OutputStream.Write($buf, 0, $buf.Length)
                    } else {
                        $res.StatusCode = 404
                    }
                }
            } catch {
                try { Write-PocketServerJson $res 500 @{ error = "$($_.Exception.Message)" } } catch { $null = $_ }
            } finally {
                if ($LogRequests) {
                    Write-Host ("{0} {1} {2} -> {3}" -f (Get-Date -Format 'HH:mm:ss'), $req.HttpMethod, $req.Url.AbsolutePath, $res.StatusCode)
                }
                try { $res.OutputStream.Close() } catch { $null = $_ }
            }
        }
    } finally {
        $listener.Stop(); $listener.Close()
        Write-Host "Server stopped." -ForegroundColor Yellow
    }
}
