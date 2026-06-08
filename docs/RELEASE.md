# Release checklist

Follow this before tagging a public release. The repo is the source of truth; releases
are versioned, CI-verified, and published with SHA256 checksums. Windows builds are
unsigned by design (free hobby project) — trust is via the official Releases page +
checksums + first-run docs; see `docs/WINDOWS-FIRST-RUN.md`.

## Pre-flight
- [ ] All CI checks green on `main` (lint, manifest-validate, jsdom, Pester ×3 OS, package-deb, package-rpm).
- [ ] `CHANGELOG.md` `[Unreleased]` reviewed and moved under a dated version heading.
- [ ] `ModuleVersion` in `src/PocketPrep/PocketPrep.psd1` bumped (semver).
- [ ] Manifests current: `pwsh ./scripts/Validate-Manifests.ps1`; firmware not flagged stale
      (the monthly `firmware-check` workflow has not opened an "out of date" issue).
- [ ] **Real-device UAT (#47) recorded** in `docs/UAT-RESULTS.md` for this version
      (Windows/Linux/macOS + a real Pocket boot). **Release gate — do not ship without it.**
- [ ] Known limitations (below) reviewed for accuracy.

## Build & verify
- [ ] `pwsh ./scripts/Build-Release.ps1` → `dist/AnaloguePocketSDCardPrepper-<ver>.zip`.
- [ ] `bash scripts/Build-Deb.sh` and (on Fedora) `bash scripts/Build-Rpm.sh`.
- [ ] Generate checksums: `sha256sum dist/* > dist/SHA256SUMS` (the `release` workflow does
      this automatically).
- [ ] Link `docs/WINDOWS-FIRST-RUN.md` in the release notes (download → verify checksum →
      unblock → run). Windows artifacts are unsigned by design — no signing step.

## Publish
- [ ] Tag `vX.Y.Z` and push the tag. **The `release` workflow then builds the zip/.deb/.rpm,
      generates `SHA256SUMS`, and creates the GitHub Release automatically** (it first checks
      the tag matches `ModuleVersion` and that manifests validate). You can also run it via
      `workflow_dispatch` against an existing tag.
- [ ] After it runs, smoke-install at least the `.deb` and the zip "run from source" path on a clean machine.
- [ ] Confirm `SHA256SUMS` is attached to the Release.

## Rollback
- Previous releases remain on the Releases page; users reinstall the prior version's
  artifact. The tool is non-destructive (copies only) and stateless, so rollback is just
  "use the older build". No data migration is involved.

## Versioning
Semantic versioning. Bump: PATCH for fixes, MINOR for new features/manifests, MAJOR for
breaking engine/API or CLI changes.
