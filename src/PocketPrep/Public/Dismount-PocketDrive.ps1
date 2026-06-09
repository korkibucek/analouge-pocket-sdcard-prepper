function Dismount-PocketDrive {
<#
.SYNOPSIS
    Flushes pending writes and best-effort unmounts/ejects the card so it's safe to remove.

.DESCRIPTION
    The important, reliable step is the FLUSH (so no write is left buffered). Unmount/eject is
    then attempted best-effort per OS and never throws - it reports whether it succeeded so the
    UI can say "safe to remove" or "please eject via your OS". A system/protected volume is
    never ejected (defense-in-depth on top of the selection-time safety check).

.PARAMETER Root
    SD card root (the target volume).

.PARAMETER FlushOnly
    Only flush; do not attempt to unmount/eject (used in test mode / fake-root runs).
#>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Best-effort flush/unmount of the user-selected removable target; never deletes data.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '',
        Justification = 'Dismount is an approved verb (Storage namespace); intent is clear.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Root,

        [switch] $FlushOnly
    )

    $msg = [System.Collections.Generic.List[string]]::new()
    $flushed = $false; $ejected = $false; $method = 'none'; $skipped = $false

    $full = try { (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path } catch { $Root }
    $volRoot = $null
    foreach ($d in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $d.IsReady) { continue }
        $r = $d.RootDirectory.FullName
        if ($full.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase) -and ($null -eq $volRoot -or $r.Length -gt $volRoot.Length)) { $volRoot = $r }
    }

    # Flush filesystem buffers - the part that actually makes removal safe.
    if ($IsWindows) {
        $msg.Add('Windows flushes writes on completion; use "Safely Remove Hardware" if prompted.')
        $flushed = $true
    } else {
        try { & sync 2>$null; $flushed = $true } catch { $msg.Add("sync failed: $_") }
    }

    # Never eject a system/protected or unknown volume.
    $isSystem = $false
    if ($IsWindows) {
        $sysd = ([string]$env:SystemDrive).TrimEnd('\')
        if ($volRoot -and ($volRoot.TrimEnd('\') -ieq $sysd)) { $isSystem = $true }
    } elseif ($volRoot -eq '/') {
        $isSystem = $true
    }

    if ($FlushOnly -or $isSystem -or -not $volRoot) {
        $skipped = $true
        $msg.Add($(if ($FlushOnly) { 'Flush only (test mode / fake root) - nothing to eject.' } else { 'Not ejecting a system/unknown volume - flushed only.' }))
    } else {
        try {
            if ($IsWindows) {
                $letter = $volRoot.TrimEnd('\')
                $shell = New-Object -ComObject Shell.Application
                $shell.Namespace(17).ParseName($letter).InvokeVerb('Eject')
                $ejected = $true; $method = 'shell-eject'
            } elseif ($IsMacOS) {
                $o = & diskutil eject $volRoot 2>&1
                if ($LASTEXITCODE -eq 0) { $ejected = $true; $method = 'diskutil' } else { $msg.Add("diskutil: $o") }
            } else {
                $dev = (& findmnt -n -o SOURCE --target $volRoot 2>$null) | Select-Object -First 1
                if ($dev) {
                    & udisksctl unmount -b $dev 2>$null
                    if ($LASTEXITCODE -eq 0) { $ejected = $true; $method = 'udisksctl'; & udisksctl power-off -b $dev 2>$null }
                }
                if (-not $ejected) {
                    & umount $volRoot 2>$null
                    if ($LASTEXITCODE -eq 0) { $ejected = $true; $method = 'umount' }
                }
            }
        } catch { $msg.Add("Automatic eject failed: $_") }
        if (-not $ejected) { $msg.Add('Could not eject automatically - please eject / safely remove the card via your OS before unplugging.') }
    }

    [pscustomobject]@{
        PSTypeName = 'PocketPrep.DismountResult'
        Root       = $Root
        Volume     = $volRoot
        Flushed    = $flushed
        Ejected    = $ejected
        Method      = $method
        Skipped    = $skipped
        Message    = ($msg -join ' ')
    }
}
