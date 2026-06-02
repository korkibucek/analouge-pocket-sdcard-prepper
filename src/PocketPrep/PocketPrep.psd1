@{
    RootModule        = 'PocketPrep.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b6f2c1a4-9d3e-4c2b-8a17-3f0e6d2c9a55'
    Author            = 'Analogue Pocket SD Card Prepper contributors'
    CompanyName       = 'Community project'
    Copyright         = '(c) 2026 korkibucek. MIT License.'
    Description       = 'Engine for preparing an Analogue Pocket SD card: safe drive detection, filesystem/emptiness validation, openFPGA folder structure, firmware install, and ROM import. Not affiliated with Analogue.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Get-PocketRemovableDrive',
        'Test-PocketDriveSafety',
        'Test-PocketFilesystem',
        'Test-PocketCardEmpty',
        'New-PocketFolderStructure',
        'Get-PocketFirmwareManifest',
        'Resolve-PocketFirmwareRelease',
        'Test-PocketFirmwareFile',
        'Install-PocketFirmware',
        'Get-PocketSystem',
        'New-PocketRomCopyPlan',
        'Invoke-PocketRomCopyPlan',
        'New-PocketTarget',
        'New-PocketLogger',
        'Write-PocketLog',
        'New-PocketInstallSummary'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('AnaloguePocket', 'openFPGA', 'SDCard', 'retrogaming')
            ProjectUri = 'https://github.com/korkibucek/analouge-pocket-sdcard-prepper'
        }
    }
}
