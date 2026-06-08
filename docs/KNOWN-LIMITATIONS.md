# Known limitations

Honest list of what the tool does **not** do or where it needs care, as of the current version.

## Hardware / platform
- **Live drive detection is OS-native**: Windows (Storage CIM), Linux (`lsblk`), macOS
  (`system_profiler`). It is exercised in CI with fixtures/fakes; real-device behaviour is
  validated via manual UAT (`docs/UAT.md`).
- **Card readers vary.** Some built-in/USB readers present the card as a *fixed* disk. The
  tool flags likely cards and guides you to the advanced override, but you must confirm the
  drive is really your card before proceeding.
- **macOS detection** is fixture-tested, not yet hardware-confirmed in this project's CI.

## Firmware
- Firmware data lives in a manifest. A monthly CI check and an in-app staleness warning
  flag when it's behind, but if neither has run you could install an older version — check
  <https://www.analogue.co/support/pocket/firmware> and use offline mode if newer.
- Firmware is verified by **MD5** (that's what Analogue publishes) plus size, before and
  after writing to the card.

## openFPGA platform-ids
- ROM destinations use `Assets/<platform-id>/common`, but **platform-ids are defined by
  each core**, not standardised by Analogue. The manifest uses common community values;
  once a core is installed the tool can read its real `platform_ids` to verify. Confirm if
  you use an unusual core.

## Systems / cores
- **Neo Geo, arcade (JT cores), and CD-based systems are experimental**: they need BIOS
  files and/or specific romset layouts the tool does not fully manage. Treat them as
  advanced/verify-manually. Core *installation* covers the **full community inventory** (install one or all at once); installing everything is a large download (set `GITHUB_TOKEN` to avoid GitHub API rate limits).
- Cores are downloaded from their authors' GitHub releases (no publisher checksums unless a
  release is pinned with a SHA-256 in the manifest); integrity otherwise relies on HTTPS.
- BIOS files are never copied automatically.

## Web UI / server
- The local web server is **single-threaded** (single-user localhost tool): a long
  download blocks other requests while it runs. The UI shows clear progress and downloads
  have timeouts, so it cannot hang silently or forever. (True async is tracked in #82.)
- The web UI has **not** had a full accessibility/browser-matrix audit (tracked separately).

## Distribution
- Windows builds are **unsigned by design** (free hobby project — no code-signing cert):
  expect a SmartScreen / "Unblock" prompt on first run. Verify the download with the
  published `SHA256SUMS` and follow `docs/WINDOWS-FIRST-RUN.md`.
- The `.deb`/`.rpm` declare PowerShell as a **weak** dependency (it isn't in default repos);
  install PowerShell 7 separately if prompted.

## Scope
- The tool **prepares folders and copies user-provided ROMs only**. It never downloads or
  supplies ROMs, and never formats, wipes, or deletes (except the explicit, heavily-guarded
  `Clear-PocketCard` / `-CleanFirst`).
