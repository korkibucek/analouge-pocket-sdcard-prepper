# Pure parser for `lsblk -J -b` JSON (Linux). Kept separate from the command call so
# it can be unit-tested with captured fixtures on any OS.

function ConvertFrom-PocketLsblk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Json
    )

    $data = $Json | ConvertFrom-Json
    $records = [System.Collections.Generic.List[object]]::new()

    function Get-Mountpoint($node) {
        # lsblk uses 'mountpoint' (singular) on older versions and 'mountpoints'
        # (array) on newer ones.
        if ($node.PSObject.Properties['mountpoint'] -and $node.mountpoint) { return [string]$node.mountpoint }
        if ($node.PSObject.Properties['mountpoints']) {
            $mp = @($node.mountpoints | Where-Object { $_ })
            if ($mp.Count -gt 0) { return [string]$mp[0] }
        }
        return $null
    }

    function Walk($node, $parentRemovable) {
        $rm  = [bool]$node.rm
        $hot = [bool]$node.hotplug
        $tran = [string]$node.tran
        $removable = $rm -or $hot -or ($tran -ieq 'usb') -or $parentRemovable
        $mount = Get-Mountpoint $node

        if ($mount) {
            $records.Add([pscustomobject]@{
                DriveLetter = $mount
                RootPath    = $mount
                Label       = [string]$node.label
                FileSystem  = [string]$node.fstype
                SizeBytes   = [int64]($node.size ?? 0)
                FreeBytes   = [int64]($node.fsavail ?? 0)
                IsRemovable = [bool]$removable
                BusType     = $tran
                MediaType   = [string]$node.type
            })
        }
        foreach ($child in @($node.children)) {
            if ($child) { Walk $child $removable }
        }
    }

    foreach ($dev in @($data.blockdevices)) {
        if ($dev) { Walk $dev $false }
    }
    return $records
}
