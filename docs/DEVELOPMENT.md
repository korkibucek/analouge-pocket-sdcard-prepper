# Development

## Setup

```powershell
# PowerShell 7.2+ required: https://aka.ms/powershell
git clone https://github.com/korkibucek/analouge-pocket-sdcard-prepper.git
cd analouge-pocket-sdcard-prepper
pwsh ./scripts/Install-DevDeps.ps1     # installs Pester 5
Import-Module ./src/PocketPrep/PocketPrep.psd1 -Force
Get-Command -Module PocketPrep
```

## Project layout

See [ARCHITECTURE.md](ARCHITECTURE.md). One exported function per file in
`src/PocketPrep/Public/`; hardware/CIM and shared helpers in `Private/`.

## Conventions

- Public functions are `Verb-PocketNoun` and use approved PowerShell verbs.
- Keep logic pure where possible; isolate side effects (CIM, file I/O, network).
- Add comment-based help to public functions.
- Every behaviour change needs a Pester test.
- Match the existing style (4-space indent, `[CmdletBinding()]`, explicit param blocks).

## Running things

```powershell
pwsh ./scripts/Run-Tests.ps1          # tests
pwsh ./src/Start-PocketPrep.ps1 -TestMode -DryRun   # wizard, safe
pwsh ./scripts/Build-Release.ps1      # produce dist/ zip
```

## Branches & commits

`feature/…`, `fix/…`, `docs/…`, `test/…`, `infra/…`; commits like
`feat: …`, `fix: …`, `docs: …`, `test: …`. Link issues in PRs and close them only
when acceptance criteria are met.

## Backlog

GitHub Issues is the canonical backlog. Don't bury discovered work in comments —
open a new issue.
