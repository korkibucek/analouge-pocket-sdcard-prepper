# Changelog

All notable changes to this project are documented here.
Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- MIT `LICENSE` (closes #16).
- **openFPGA core installation** (closes #13): `manifests/cores.json` (+ schema) and
  `Get-PocketCoreManifest`, `Resolve-PocketCore`, `Test-PocketCoreZip`,
  `Install-PocketCore`. Installs a curated set of cores either by downloading the core's
  official GitHub release zip or from a user-supplied `.zip` (offline). Extraction is
  zip-slip-protected and non-destructive (skips existing files unless `-Overwrite`),
  with `-DryRun`. Wizard gained an optional core-install step; install summary now
  reports cores. Core download verified end-to-end against a real release (agg23.NES).
- Corrected `suggestedCore` identifiers in `systems.json` to match real core names.
- **Cross-platform drive detection** (closes #19): Linux (`lsblk`) and macOS
  (`system_profiler`) providers + a `RootPath` field on drive objects.
- **Cross-platform safety** (closes #20): `Test-PocketDriveSafety` rejects protected
  Linux/macOS mountpoints (and the Windows system drive); mountpoint-based targets.
- **Local web server + REST API** (closes #21): `Start-PocketPrepServer` (HttpListener,
  127.0.0.1 only) exposing the engine as JSON. Per-session token required on every
  `/api` call, with Host/Origin checks (CSRF / DNS-rebinding defence). Pure routing
  (`Invoke-PocketApiRoute`) and auth (`Test-PocketApiRequest`) are fully unit-tested.
- **Browser wizard UI** (closes #22): a vanilla-JS single-page wizard served by the
  local server (drive/target selection, card checks, firmware, folders, cores, ROM
  import, summary) with loading/empty/error states and no external dependencies. Added
  `POST /api/target` so the target can be chosen in the browser (mutable server state).
- **Cross-platform launchers & packaging** (closes #23): `Start-PocketPrepWeb.ps1`
  entry script; `PocketPrep.cmd` now launches the web UI (`cli` arg for the wizard);
  `scripts/pocketprep.sh` launcher for Linux/macOS (Unix-style flags); a `.desktop`
  entry; and `scripts/Build-Deb.sh` / `scripts/Build-Rpm.sh` producing native packages
  that install a `pocketprep` command and depend on `powershell`.

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
