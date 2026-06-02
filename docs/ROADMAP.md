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
- **openFPGA core installation** (#13): `cores.json` manifest + `Install-PocketCore`
  (offline zip or GitHub-release download), zip-slip-safe, non-destructive, for a
  curated set. Tested + a real download validated.

## Next
- **Expand the core set** and add an **updater** (re-install when a newer release exists).
- **Per-core platform-id discovery**: read installed cores' platform definitions to
  auto-fill/verify ROM destinations.
- **GUI layer** (#15): a WPF (or .NET) front-end over the existing engine. The engine
  API is already GUI-agnostic.
- **Optional verified manual wipe/clean** with strong safeguards (typed-label
  confirmation, removable-only hard gate, dry-run preview).

## Maybe later
- ROM library scanning / no-intro-style matching
- Save backup/restore from the card
- Firmware "latest" auto-check against the official page (with manual confirmation)
