# Architecture

## Overview

The project is a **PowerShell 7 engine module** (`PocketPrep`) plus a thin
**interactive CLI wizard** (`src/Start-PocketPrep.ps1`). All real work lives in the
module as small, pure, individually testable functions. The wizard only handles
prompts and sequencing; it contains no business logic that isn't also callable
directly.

### Why PowerShell 7 (not C#/.NET or a GUI yet)

- The core logic (drive filtering, safety rules, validation, path generation,
  copy planning, manifest parsing) is **pure data transformation** and is fully
  unit-testable with Pester — including in CI on Linux, with no Windows hardware.
- Users need **one dependency** (PowerShell 7), not a compiled runtime.
- The only Windows-specific piece (live drive enumeration via the Storage/CIM
  cmdlets) is **isolated behind a provider boundary**, so tests inject fake data.
- A GUI (WPF, or a .NET front-end) can be layered on the *same engine* later
  without rewriting logic. Shipping an untested Windows-only GUI now would violate
  the project's "don't claim untested" rule. See [ROADMAP.md](ROADMAP.md).

## Components

```
src/PocketPrep/
  Public/    one exported function per file (the engine API)
  Private/   helpers: drive provider (CIM), MD5, shared constants
src/Start-PocketPrep.ps1   interactive wizard (UI layer only)
manifests/                 firmware.json, systems.json, JSON schemas (data layer)
tests/                     Pester suite (one file per component)
scripts/                   Run-Tests, Install-DevDeps, Build-Release
```

Layer separation:

| Layer | Where |
|---|---|
| UI | `Start-PocketPrep.ps1`, `PocketPrep.cmd` |
| Drive detection | `Get-PocketRemovableDrive` + `Private/Get-PocketRawDriveData` (CIM) |
| Validation | `Test-PocketDriveSafety`, `Test-PocketFilesystem`, `Test-PocketCardEmpty` |
| Firmware | `Get-PocketFirmwareManifest`, `Resolve-PocketFirmwareRelease`, `Test-PocketFirmwareFile`, `Install-PocketFirmware` |
| ROM copy | `Get-PocketSystem`, `New-PocketRomCopyPlan`, `Invoke-PocketRomCopyPlan` |
| Cores | `Get-PocketCoreManifest`, `Resolve-PocketCore`, `Test-PocketCoreZip`, `Install-PocketCore` |
| Folders | `New-PocketFolderStructure` |
| Config/data | `manifests/*.json` |
| Logging | `New-PocketLogger`, `Write-PocketLog` |
| Reporting | `New-PocketInstallSummary` |

## Data flow

```mermaid
flowchart TD
    A[Start-PocketPrep wizard] --> B{Test mode?}
    B -- yes --> T[New-PocketTarget -TestMode<br/>fake SD root]
    B -- no --> D[Get-PocketRemovableDrive] --> S[Test-PocketDriveSafety]
    S -- unsafe --> X[Abort]
    S -- safe --> T2[New-PocketTarget<br/>real card root]
    T --> V
    T2 --> V[Test-PocketFilesystem<br/>Test-PocketCardEmpty]
    V --> F[Install-PocketFirmware<br/>download MD5-verified OR local file]
    F --> FS[New-PocketFolderStructure]
    FS --> R[per system: New-PocketRomCopyPlan -> Invoke-PocketRomCopyPlan]
    R --> SU[New-PocketInstallSummary + log]
```

## Key design choices

- **Plan/execute split for ROMs.** `New-PocketRomCopyPlan` is pure and returns a
  plan; `Invoke-PocketRomCopyPlan` performs it. This makes dry-run trivial and the
  matching logic testable without copying anything.
- **Provider boundary for hardware.** `Get-PocketRemovableDrive -DataProvider {…}`
  accepts injected data; the default provider is the only code that calls CIM.
- **Manifest-driven everything.** Firmware URLs/checksums and system definitions are
  JSON, validated on load, so non-developers can update them.
- **Non-destructive by construction.** No function deletes, formats, or repartitions.
  The most that happens is `Copy-Item` into a folder and `New-Item` for directories.

## Error handling

Functions throw with specific, actionable messages (missing manifest field, MD5
mismatch, unsafe drive, missing source folder). The wizard catches per-step failures
(e.g. firmware download) and continues where sensible, logging the error.

## Logging

`New-PocketLogger` returns an object holding a file path and an in-memory entry list;
`Write-PocketLog` appends timestamped `[LEVEL] message` lines to both. The in-memory
list lets tests assert on logged actions. Secrets are never logged (there are none).

## Testing model

See [testing.md](testing.md). Every pure component has a Pester file; an end-to-end
test runs the whole flow against a fake SD root.

## Future extension points

- `manifests/cores.json` + a core installer (issue #13).
- A GUI front-end reusing the engine API.
- Additional systems by editing `systems.json`.
