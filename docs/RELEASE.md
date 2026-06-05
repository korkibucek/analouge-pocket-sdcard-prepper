# Release checklist

Follow this before tagging a public release. The repo is the source of truth; releases
are versioned, CI-verified, and (eventually) signed.

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
- [ ] Generate checksums: `sha256sum dist/* > dist/SHA256SUMS`.
- [ ] Windows: sign artifacts once a code-signing cert exists (#84). Until then, link
      `docs/WINDOWS-FIRST-RUN.md` in the release notes.

## Publish
- [ ] Tag `vX.Y.Z` and push the tag.
- [ ] Create a GitHub Release with the changelog section + the zip/.deb/.rpm + `SHA256SUMS`.
- [ ] Smoke-install at least the `.deb` and the zip "run from source" path on a clean machine.

## Rollback
- Previous releases remain on the Releases page; users reinstall the prior version's
  artifact. The tool is non-destructive (copies only) and stateless, so rollback is just
  "use the older build". No data migration is involved.

## Versioning
Semantic versioning. Bump: PATCH for fixes, MINOR for new features/manifests, MAJOR for
breaking engine/API or CLI changes.
