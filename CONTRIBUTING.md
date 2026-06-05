# Contributing

Thanks for helping improve the Analogue Pocket SD Card Prepper! This is a safety-first
tool that writes to people's SD cards, so correctness and tests matter.

## Dev setup
- Install **PowerShell 7.2+** (`pwsh`) — see <https://aka.ms/powershell>.
- `pwsh ./scripts/Install-DevDeps.ps1` (installs Pester 5).
- `Import-Module ./src/PocketPrep/PocketPrep.psd1 -Force`.
- See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Before you open a PR
Run these locally (CI runs the same):
```powershell
pwsh ./scripts/Invoke-Lint.ps1          # PSScriptAnalyzer (must be clean)
pwsh ./scripts/Validate-Manifests.ps1   # manifests
pwsh ./scripts/Run-Tests.ps1            # Pester (add tests for new behaviour)
```
If you touch the web UI: `cd tests/web && npm install && npm test` (jsdom).

## Conventions
- Branches: `feature/…`, `fix/…`, `docs/…`, `test/…`, `infra/…`.
- Commits/PR titles: `feat: …`, `fix: …`, `docs: …`, `test: …`, `ci: …`.
- One exported function per file under `src/PocketPrep/Public/`; helpers/OS-specific code
  in `Private/`. Keep logic pure where possible; isolate side effects (I/O, network, CIM).
- **Add or update tests** for any behaviour change. Don't claim something works without tests.
- Update docs when behaviour/setup/architecture changes.

## Safety rules (non-negotiable)
- Never add a code path that formats, wipes, repartitions, or deletes user data except the
  existing heavily-guarded `Clear-PocketCard`. No destructive defaults.
- The tool copies user-provided ROMs only; it never downloads or bundles ROMs.
- Don't commit secrets or build artifacts.

## CI / merging
`main` is branch-protected: all CI checks (lint, manifest validation, jsdom, Pester on
Windows/Linux/macOS, `.deb`/`.rpm` packaging) must pass before merge. Don't merge red.
