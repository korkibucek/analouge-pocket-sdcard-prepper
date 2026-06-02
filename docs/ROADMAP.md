# Roadmap

Tracked in detail on [GitHub Issues](https://github.com/korkibucek/analouge-pocket-sdcard-prepper/issues).

## v0.1.0 — MVP (done)
- Safe drive detection + safety gate
- Filesystem + emptiness validation
- Manifest-driven firmware install (download + offline), MD5-verified
- openFPGA folder structure
- Data-driven system manifest + ROM import wizard
- Logging + summary
- Safe test mode + 48-test Pester suite
- Documentation + CI

## Next
- **openFPGA core installation** (#13): `cores.json` manifest, download/place cores,
  assets, platforms; per-core platform-ids; BIOS handling; updater. Implement for a
  small, well-tested supported set first.
- **GUI layer**: a WPF (or .NET) front-end over the existing engine. The engine API is
  already GUI-agnostic.
- **Per-core platform-id discovery**: read installed cores' platform definitions to
  auto-fill/verify ROM destinations instead of relying solely on the manifest.
- **Choose and add a LICENSE** (e.g. MIT) if the project is to be open source.
- **Optional verified manual wipe/clean** with strong safeguards (typed-label
  confirmation, removable-only hard gate, dry-run preview).

## Maybe later
- ROM library scanning / no-intro-style matching
- Save backup/restore from the card
- Firmware "latest" auto-check against the official page (with manual confirmation)
