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
- **CI matrix + docs** (closes #24): CI now runs the Pester suite on Windows, Linux,
  and macOS. Added `docs/SECURITY.md` (web server threat model) and updated
  ARCHITECTURE/ROADMAP/README for the web UI and cross-platform support.
- **Installed-core inventory, update check & platform-id discovery** (closes #31):
  `Get-PocketInstalledCore` (reads `Cores/<id>/core.json` for version + `platform_ids`),
  `Compare-PocketVersion`, `Test-PocketPlatformIdInstalled`, and `Get-PocketCoreUpdateStatus`
  (compares installed cores to their latest GitHub release). Added `GET /api/installed-cores`.
  Refactored GitHub release resolution into a shared `Get-PocketLatestRelease` helper.
  Verified end-to-end against agg23.NES (inventory, platform-id discovery, update check).
- **Surfaced cores in the UIs** (closes #33): web UI and CLI now show already-installed
  cores + versions, offer "check for updates" / reinstall-update (overwrite), and warn in
  the ROM step when no installed core provides a system's platform. Added
  `GET /api/cores/updates`, a non-breaking `PlatformProvided` flag on `/api/rom/plan`, and
  `overwrite` support on `/api/cores/install`.

- **Linting** (closes #35): PSScriptAnalyzer ruleset (`PSScriptAnalyzerSettings.psd1`),
  `scripts/Invoke-Lint.ps1`, and a CI lint job. Code is lint-clean; three rules are
  excluded with documented justifications (Write-Host for the interactive UI, explicit
  `-DryRun` instead of ShouldProcess, and MD5 required to match Analogue's checksums).

- **Manifest validation** (closes #36): `scripts/Validate-Manifests.ps1` checks all
  three manifests (structure + consistency) and is run in CI; a `ManifestIntegrity`
  test covers the shipped manifests and a broken fixture.

- **Update-all-cores** (closes #37): `Update-PocketCore` reinstalls every installed core
  that has a newer GitHub release (download + overwrite), with `-DryRun`. Added
  `POST /api/cores/update-all`, an "Update all" button in the web UI, and a CLI prompt.
  Verified end-to-end (0.9.0 → 1.0.1 against agg23.NES).

- **Save backup & restore** (closes #38): `Backup-PocketSaves` (copies `Saves/`, and
  optionally `Memories/`, to a timestamped folder) and `Restore-PocketSaves` (copies
  back, skip-existing unless `-Overwrite`). Copy-only, never deletes; both support
  `-DryRun`. Added `POST /api/saves/backup` and `/api/saves/restore`; the CLI offers a
  backup when the card isn't empty, and the web UI shows a backup widget on a non-empty card.

- **Headless web UI test** (closes #39): `tests/web/` runs `app.js` in jsdom with a
  stubbed fetch and asserts the wizard bootstraps, calls the API, and renders the first
  step. Runs in CI on Node 20; dev-only (not a runtime dependency).

- **Guarded card clean/wipe** (closes #40): `Clear-PocketCard` — the only destructive
  function — deletes a card's contents to allow re-prepping, gated by a removable+non-system
  safety re-check, a typed confirmation token (label or root path), contents-only deletion
  (skips OS entries), mandatory `-DryRun` preview, and WARN-level logging. Never default;
  exposed only via the CLI `-CleanFirst` flag and intentionally **not** over the web API.
  Documented in docs/safety-model.md.

- **Robust downloads** (closes #50): shared HTTP layer (`Invoke-PocketHttp`) with
  timeouts, bounded retry on transient failures, and size caps; clear GitHub
  rate-limit/offline errors + optional `GITHUB_TOKEN`.
- **Free-space preflight** (closes #49): firmware, ROM, and core writes now check the
  card has room first and refuse with a clear message instead of failing mid-write.
  The ROM plan exposes `DestinationFreeBytes`/`FitsInDestination`; CLI and web UI warn
  before copying. `Invoke-PocketRomCopyPlan -SkipSpaceCheck` overrides.

- **Write verification + safe-eject** (closes #52): firmware is re-hashed ON THE CARD after writing (a corrupt/truncated copy now fails loudly with `OnCardVerified`); ROM copies are size-verified post-copy (truncation counts as failed); the summary tells the user to safely eject/unmount before removing the card.

- **Windows detection coverage** (closes #48): extracted the removable-classification into a pure, unit-tested `ConvertTo-PocketWindowsDriveRecord`; added a Windows-runner integration test that executes the real CIM detection path and asserts shape/no-throw. Locked/RAW volumes fall back gracefully.

- **Installable packages** (closes #54): `.deb`/`.rpm` now declare PowerShell as a weak dependency (`Recommends`) instead of a hard one, so they install on stock distros where `pwsh` is not in the default repos; a postinst/posttrans message guides the user to install PowerShell 7 if missing.

- **Wizard tests** (closes #55): the `Start-PocketPrep.ps1` CLI wizard is now tested end-to-end as a subprocess with scripted stdin against a fake SD root — happy path, real Game Boy ROM import, and the abort-on-decline branch for a non-empty card.

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
