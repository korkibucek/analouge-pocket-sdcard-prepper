# Writes a JSON response body to an HttpListener response. Used by Start-PocketPrepServer.
function Write-PocketServerJson {
    [CmdletBinding()]
    param($Response, [int]$Status, $Body)
    $Response.StatusCode = $Status
    $Response.ContentType = 'application/json; charset=utf-8'
    $json = $Body | ConvertTo-Json -Depth 10 -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.OutputStream.Write($buf, 0, $buf.Length)
}
