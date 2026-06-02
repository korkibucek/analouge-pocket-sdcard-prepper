# Roadmap

Tracked in detail on [GitHub Issues](https://github.com/korkibucek/analouge-pocket-sdcard-prepper/issues).

## v0.1.0 — MVP (done)
- Safe drive detection + safety gate
- Filesystem + emptiness validation
- Manifest-driven firmware install (download + offline), MD5-verified
- openFPGA folder structure
- Data-driven system manifest + ROM import wizard
- Logging + summary
- Safe test mode + Pester test suite
- Documentation + CI

## Done after MVP
- **MIT licence** (#16).
- **openFPGA core installation** (#13): `cores.json` + `Install-PocketCore` (offline zip
  or GitHub-release download), zip-slip-safe, non-destructive. Tested + real download.
- **Cross-platform** (#19, #20): Linux (`lsblk`) and macOS (`system_profiler`) drive
  detection; mountpoint-aware safety. CI on Windows/Linux/macOS (#24).
- **Local web UI** (#21, #22): localhost, token-secured REST API + browser wizard —
  replaces the old WPF GUI plan (#15).
- **Launchers + packaging** (#23): Windows/.deb/.rpm/macOS launchers and package scripts.

## Next
- **Expand the core set** and add an **updater** (re-install when a newer release exists).
- **Per-core platform-id discovery**: read installed cores' platform definitions to
  auto-fill/verify ROM destinations.
- **Optional verified manual wipe/clean** with strong safeguards (typed-label
  confirmation, removable-only hard gate, dry-run preview).
- **Native installers** beyond .deb/.rpm (e.g. a signed Windows MSI, a macOS .pkg).

## Maybe later
- ROM library scanning / no-intro-style matching
- Save backup/restore from the card
- Firmware "latest" auto-check against the official page (with manual confirmation)
