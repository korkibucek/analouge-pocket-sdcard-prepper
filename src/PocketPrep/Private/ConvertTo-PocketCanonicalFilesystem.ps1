# Normalises the many OS-specific filesystem name spellings to a canonical token so the
# acceptability check works on Windows, Linux (lsblk: 'vfat'), and macOS
# ('MS-DOS (FAT32)', 'ExFAT'). Returns one of: EXFAT, FAT32, FAT16, or the uppercased input.

function ConvertTo-PocketCanonicalFilesystem {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $FileSystem)

    $u = ($FileSystem ?? '').Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($u)) { return '' }

    switch -Regex ($u) {
        'EXFAT'                              { return 'EXFAT' }
        'FAT\s*32|MS-DOS \(FAT32\)'          { return 'FAT32' }
        'FAT\s*16|FAT\s*12|MS-DOS \(FAT16\)' { return 'FAT16' }
        # Generic FAT spellings (lsblk 'vfat', 'msdos', bare 'FAT'/'MS-DOS') are, on the
        # SD cards this tool targets, virtually always FAT32; treat them as FAT32.
        '^(VFAT|MSDOS|MS-DOS|FAT)$'          { return 'FAT32' }
        default                              { return $u }
    }
}
