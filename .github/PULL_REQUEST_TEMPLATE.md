## Summary
What this changes and why. Closes #<issue>.

## Changes
-

## Testing
- [ ] `pwsh ./scripts/Invoke-Lint.ps1` clean
- [ ] `pwsh ./scripts/Run-Tests.ps1` green (tests added/updated for the change)
- [ ] `pwsh ./scripts/Validate-Manifests.ps1` (if manifests changed)
- [ ] web UI test (if `web/` changed): `cd tests/web && npm test`

## Docs
- [ ] Updated docs/README/CHANGELOG if behaviour, setup, or architecture changed

## Safety
- [ ] No new destructive defaults; copies user-provided ROMs only
