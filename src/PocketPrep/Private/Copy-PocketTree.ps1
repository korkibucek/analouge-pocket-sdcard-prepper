# Shared recursive file-tree copy used by Backup-PocketSaves and Restore-PocketSaves.
# Copies every file under $Source to the mirrored path under $Destination, creating parent
# directories, skipping existing files unless -Overwrite, and supporting -DryRun. Returns
# the relative paths copied and skipped. (ROM/core copy paths have extra concerns -
# size verification, problem-skipping, zip extraction - so they intentionally don't use this.)

function Copy-PocketTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination,
        [switch] $Overwrite,
        [switch] $DryRun
    )

    $copied  = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return [pscustomobject]@{ Copied = @(); Skipped = @() }
    }
    $srcFull = (Resolve-Path -LiteralPath $Source).Path

    foreach ($file in Get-ChildItem -LiteralPath $srcFull -Recurse -File -ErrorAction SilentlyContinue) {
        $rel  = $file.FullName.Substring($srcFull.Length).TrimStart([char]'\', [char]'/')
        $dest = Join-Path $Destination $rel
        if ((Test-Path -LiteralPath $dest -PathType Leaf) -and -not $Overwrite) {
            $skipped.Add($rel); continue
        }
        $copied.Add($rel)
        if (-not $DryRun) {
            $dir = Split-Path -Parent $dest
            if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Copy-Item -LiteralPath $file.FullName -Destination $dest -Force:$Overwrite
        }
    }
    return [pscustomobject]@{ Copied = $copied.ToArray(); Skipped = $skipped.ToArray() }
}
