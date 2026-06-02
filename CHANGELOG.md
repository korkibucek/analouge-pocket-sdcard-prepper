# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- MIT `LICENSE` (closes #16).

## [0.1.0] - 2026-06-02

Initial MVP.

### Added
- `PocketPrep` PowerShell 7 engine module with layered, unit-testable functions:
  - Safe removable-drive detection (`Get-PocketRemovableDrive`) behind a provider
    abstraction so tests inject fake drive data.
  - Safety gate (`Test-PocketDriveSafety`) — never targets the system drive; fixed
    disks require an explicit advanced override; no destructive defaults.
  - Filesystem + emptiness checks (`Test-PocketFilesystem`, `Test-PocketCardEmpty`)
    against verified FAT32/exFAT requirements.
  - openFPGA folder-structure creation (`New-PocketFolderStructure`), idempotent, dry-run capable.
  - Manifest-driven firmware install (`Install-PocketFirmware`) with official-source-only
    download, MD5 + size validation, and an offline/manual-file mode.
  - Data-driven system manifest + ROM import (`Get-PocketSystem`,
    `New-PocketRomCopyPlan`, `Invoke-PocketRomCopyPlan`) with dry-run and skip-existing.
  - Logging (`New-PocketLogger`, `Write-PocketLog`) and install summary (`New-PocketInstallSummary`).
- Interactive CLI wizard `src/Start-PocketPrep.ps1` and Windows launcher `PocketPrep.cmd`.
- `manifests/firmware.json` (Pocket firmware 2.5) and `manifests/systems.json` (10 systems),
  with JSON schemas under `manifests/schemas/`.
- Safe **test mode** against a fake SD root, plus a 48-test Pester suite and `scripts/Run-Tests.ps1`.
- Documentation: README and `docs/` (ARCHITECTURE, safety-model, manifests, testing,
  DEVELOPMENT, TROUBLESHOOTING, ROADMAP).
- GitHub Actions CI running the Pester suite on Windows.

### Known limitations
- Automatic openFPGA **core** installation is not included (tracked in issue #13);
  the tool creates the folder structure and copies user ROMs only.
- openFPGA platform-ids are core-defined, not standardised by Analogue; manifest values
  match common community cores and may need adjustment for other cores.
- The GUI layer is deferred; this MVP ships an interactive CLI wizard.
