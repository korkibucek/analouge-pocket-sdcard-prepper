# Favourites folder naming, centralised so it can't drift across the engine.
#
# The folder is named "!Favorites" so it sorts to the TOP of the Pocket/Analogue openFPGA
# menu: in ASCII/exFAT lexical order '!' (0x21) sorts before '#' (0x23), digits and letters.
# The legacy name "Favorites" is still recognised (for migration and exclusion).

function Get-PocketFavoritesFolderName {
    # The canonical favourites folder name to write to.
    '!Favorites'
}

function Get-PocketReservedRomFolderName {
    # Tool-managed folders under a platform's common/ that are NOT part of the ROM library
    # (must be excluded from organize/scan/list). Current + legacy favourites names.
    @('!Favorites', 'Favorites')
}

function Test-PocketReservedRomPath {
    # True if $FullPath lives inside a reserved (tool-managed) folder under $Common.
    param([string] $Common, [string] $FullPath)
    foreach ($name in Get-PocketReservedRomFolderName) {
        $prefix = (Join-Path $Common $name) + [System.IO.Path]::DirectorySeparatorChar
        if ($FullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
