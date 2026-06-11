# Testing

Because this tool touches storage, **no test ever requires a real SD card or real
ROMs.** Tests use injected fake drive data and temporary folders.

## Run the suite

```powershell
pwsh ./scripts/Run-Tests.ps1        # normal output
pwsh ./scripts/Run-Tests.ps1 -CI    # detailed; exits non-zero on failure (used in CI)
```

This installs Pester 5 automatically if missing (CurrentUser scope).

## What is covered

| File | Component |
|---|---|
| `DriveDetection.Tests.ps1` | Removable-only filtering, `-IncludeFixed`, object shape (fake provider) |
| `WindowsDrives.Tests.ps1` / `CrossPlatformDrives.Tests.ps1` | CIM-shape parsing; `lsblk`/`system_profiler` fixture parsing |
| `Safety.Tests.ps1` | System-drive block, fixed-disk override, large-disk flag, no-letter |
| `Filesystem.Tests.ps1` | FAT32/exFAT accept, NTFS reject, case-insensitivity, remediation |
| `Emptiness.Tests.ps1` | Empty vs non-empty, benign-entry ignoring |
| `FolderStructure.Tests.ps1` | Folder creation, idempotency, dry-run |
| `Firmware.Tests.ps1` / `FirmwareAge.Tests.ps1` | Manifest parse/validate, release resolve, MD5/size verify, offline placement, mismatch refusal, dry-run, duplicate-firmware warning; manifest staleness |
| `Manifest.Tests.ps1` / `ManifestIntegrity.Tests.ps1` | Systems parse, destination path, lowercasing, duplicate/invalid rejection; schema-level manifest checks |
| `Rom.Tests.ps1` | Extension matching, destination, flatten, **dedupe**, **batched copy + progress**, dry-run, skip-existing, match-all (`*`) |
| `Logging.Tests.ps1` | Logger file+memory, install summary content |
| `Cores.Tests.ps1` / `CoreSet.Tests.ps1` / `CoresSupplement.Tests.ps1` | Manifest parse/resolve, zip validation, **zip-slip rejection**, offline + **BYO local-zip** install, bulk/subset install with repo+pattern dedupe, curated supplement coverage |
| `AssetPattern.Tests.ps1` | Multi-zip release asset selection (`assetPattern`: GB vs GBC, MiSTer-vs-Pocket builds) |
| `CoreUpdate.Tests.ps1` / `CoreIntegrity.Tests.ps1` / `CoreInventory.Tests.ps1` | Update detection/apply; integrity verify + repair; installed-core inventory |
| `RomOrganize.Tests.ps1` | Subfolder bucketing (cap/letter-range), idempotence, flatten-back, **filename shortening**, dry-run |
| `RegionDedupe.Tests.ps1` | Region parsing/ranking, disc-not-collapsed, region-less ignored, PAL/NTSC-J mapping, reversible quarantine |
| `Favorites.Tests.ps1` / `FavoriteSaveSync.Tests.ps1` | Save/dedupe/clear, symlink-or-copy sync, stale removal, `!Favorites` + legacy migration, organizer exclusion; save reconciliation (original = master, backup-before-overwrite) |
| `RomConfig.Tests.ps1` / `UsedCard.Tests.ps1` | Saved source mapping + rescan; onboarding a used card |
| `Profile.Tests.ps1` | Profile export/import round-trip (references only, no ROM data) |
| `CardSummary.Tests.ps1` / `RequiredFiles.Tests.ps1` / `BiosStatus.Tests.ps1` | Card breakdown; data.json-driven required-file/BIOS detection (incl. core-specific slots) |
| `BiosInstall.Tests.ps1` | User-supplied BIOS upload: declared-slot-only, exact-name rename, size verify, overwrite guard |
| `HealthReport.Tests.ps1` | One-click card audit: BIOS scoped to in-use platforms, folder-count ceilings, firmware/core checks |
| `GameImages.Tests.ps1` | Box-art scrape: index matching (exact/case/tag-stripped), cache, size cap, sanitised names |
| `ArcadeRecipes.Tests.ps1` | rom-recipes fetch + arcade romset readiness (instance `.json` / built `.rom`) |
| `CardCleanup.Tests.ps1` / `Clean.Tests.ps1` | Empty-folder/probe-only cleanup (report-don't-delete for unmanaged); `Clear-PocketCard` guards (token, removable-only, dry-run) |
| `SaveBackup.Tests.ps1` / `SaveStatePrune.Tests.ps1` | Saves backup/restore; guarded save-state prune (policy required, mandatory backup zip, dry-run) |
| `KnownPlatform.Tests.ps1` / `ImportablePlatform.Tests.ps1` | Every-core platform union; installed-core platforms |
| `DiskSpace.Tests.ps1` / `FreeSpace.Tests.ps1` / `Dismount.Tests.ps1` | Free/total space + preflight; flush + best-effort eject |
| `DirectoryListing.Tests.ps1` | Read-only folder picker |
| `Http.Tests.ps1` | Transient-error detection, bounded retry, size-capped download |
| `ImagePack.Tests.ps1` | Platform image pack install (`Platforms/_images`) |
| `ErrorPaths.Tests.ps1` | Download/IO failure handling surfaces actionable messages |
| `WebApi.Tests.ps1` | The full `Invoke-PocketApiRoute` surface + auth (`Test-PocketApiRequest`) without sockets |
| `Wizard.Tests.ps1` | CLI wizard end-to-end (subprocess, fake SD root) |
| `TestMode.Tests.ps1` | End-to-end against a fake SD root |
| `tests/web/test.mjs` | Web UI bootstrap, action menu, BIOS reference rendering, a11y hooks (jsdom) |

330+ Pester tests plus the jsdom web test, green on Windows/Linux/macOS CI.

## Web UI test (jsdom)

The browser wizard has a headless test under `tests/web/` (Node + jsdom + a stubbed
fetch) that asserts `app.js` bootstraps, calls the API, and renders without errors:

```bash
cd tests/web && npm install && npm test
```

CI runs it on Node 20. It is dev-only and not a runtime dependency.

## Accessibility (web UI)

Automated hooks are checked by the jsdom test (aria-live status region is present and
announced on each step, the panel is a focus target, and every form control has a label).
A full audit still needs a human pass:

- [ ] Complete the whole wizard with the **keyboard only** (Tab/Shift+Tab/Space/Enter).
- [ ] With a **screen reader** (NVDA/VoiceOver), confirm each step and status/error is announced.
- [ ] Run **axe**/Lighthouse and address any serious/critical issues.
- [ ] Verify **colour contrast** ≥ WCAG AA (the palette — accent `#2d7d46`, warn `#b06b00`,
      error `#b00020` on white — meets AA for text; re-check if colours change).

Status is never conveyed by colour alone (messages carry text), and focus is moved to each
new step with a visible `:focus-visible` outline.

## Test mode (manual)

```powershell
# Fake SD root in %TEMP%\PocketSDTest, nothing written:
pwsh ./src/Start-PocketPrep.ps1 -TestMode -DryRun

# Actually copy into the fake root, using the bundled placeholder ROMs:
pwsh ./src/Start-PocketPrep.ps1 -TestMode
#   When asked about Game Boy, point it at examples/fake-sd-source/GameBoy
```

## Notes for contributors

- Keep new logic in `Public/`/`Private/` functions (pure where possible) and add a
  Pester file alongside.
- Use the `-DataProvider` parameter to test drive logic without hardware.
- Network is never required: firmware tests use the offline path and locally computed
  MD5s.
