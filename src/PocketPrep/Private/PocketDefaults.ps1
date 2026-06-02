# Shared engine constants. Values verified against official Analogue documentation
# (see docs/manifests.md and README for sources).

$script:PocketDefaults = [pscustomobject]@{
    # Top-level openFPGA folders. Source:
    # https://www.analogue.co/developer/docs/directories-and-sd-folder-structure
    FolderStructure = @(
        'Assets',
        'Cores',
        'Saves',
        'Settings',
        'System',
        'Memories',
        'Presets',
        'GB Studio',
        'Platforms'
    )

    # Filesystems the Pocket accepts. Source:
    # https://www.analogue.co/support/resource/updating-firmware  ("FAT32 or ExFat")
    AcceptableFilesystems = @('FAT32', 'EXFAT')
    RecommendedFilesystem = 'exFAT'

    # Top-level entries that do NOT count as "user content" when checking emptiness.
    BenignRootEntries = @(
        'System Volume Information',
        '$RECYCLE.BIN',
        'RECYCLER',
        '.Trashes',
        '._.Trashes',
        '.Spotlight-V100',
        '.fseventsd',
        'desktop.ini',
        'Thumbs.db',
        '.DS_Store'
    )

    # A non-removable volume larger than this needs an explicit advanced override,
    # because a large fixed disk is very likely an internal/backup drive, not an SD card.
    LargeNonRemovableThresholdBytes = 512GB

    # Hosts permitted for firmware download. Official Analogue sources only.
    AllowedFirmwareHosts = @('www.analogue.co', 'analogue.co', 'assets.analogue.co')
}
