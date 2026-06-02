# Analogue Pocket SD Card Prepper

Prepare a microSD card for an **Analogue Pocket** *before your console arrives*.
Insert the card into your Windows PC, run the tool, choose what to install
(firmware, the openFPGA folder structure, and your own ROMs), then put the card
into the Pocket when it arrives and start playing immediately.

> Not affiliated with or endorsed by Analogue. "Analogue Pocket" is a product of
> Analogue, Inc. This is a community tool.

---

## ⚠️ Safety first — read this

This tool is **deliberately non-destructive**:

- It **only ever copies files into folders.**
- It **never formats, wipes, repartitions, or deletes** your data.
- It **only shows removable drives by default** and **refuses the Windows system drive** outright.
- A fixed/internal disk can only be selected with an explicit **advanced override**, and the system drive can *never* be selected.
- If the card already has files, it warns you and **leaves them in place**.
- Every action is logged.

It also does **not** provide or download ROMs. It copies ROMs **you already own**,
from folders you point it at. You are responsible for the legality of your ROMs.

---

## What it does

1. Detects removable drives / SD cards (or uses a **fake SD root** for testing).
2. Lets you select the correct card and shows letter, label, filesystem, size, free space and removability.
3. Runs safety checks before doing anything.
4. Checks the filesystem (**FAT32 or exFAT**) and whether the card is empty.
5. Installs the latest supported **Pocket firmware** — official download (MD5-verified) or a file you already have (offline mode).
6. Creates the expected **openFPGA folder structure**.
7. Walks you through **ROM import per system**, copying your ROMs into the correct folders.
8. Prints a **summary** and writes a **log** (locally, and optionally to the card).

## What it does NOT do (yet)

- It does **not** automatically install openFPGA **cores** (tracked in [issue #13](https://github.com/korkibucek/analouge-pocket-sdcard-prepper/issues/13)). You add cores yourself; this tool sets up the folders and your ROMs.
- It does **not** format cards. If the filesystem is wrong, it tells you how to fix it.
- It does **not** ship a graphical UI in this version — it's a clear interactive wizard (GUI is on the roadmap, [issue ...]).

---

## Requirements

- **Windows 10 or 11** (live drive detection uses Windows storage APIs).
- **PowerShell 7.2+** (`pwsh`). Install from <https://aka.ms/powershell>.
- **No Administrator rights needed** for the normal copy workflow. (Reading drive
  metadata and copying files to a removable card do not require elevation.)

The cross-platform *logic* and tests also run on Linux/macOS via PowerShell 7, which
is how the project is tested in CI — but **live SD detection is Windows-only**.

---

## How to run

### Easiest (Windows)
Download/clone the repo and **double-click `PocketPrep.cmd`**. It launches the wizard
with the right execution policy. If `pwsh` isn't installed it tells you where to get it.

### From source
```powershell
git clone https://github.com/korkibucek/analouge-pocket-sdcard-prepper.git
cd analouge-pocket-sdcard-prepper
pwsh ./src/Start-PocketPrep.ps1
```

### Try it safely with no SD card (test mode)
```powershell
pwsh ./src/Start-PocketPrep.ps1 -TestMode -DryRun
```
This uses a fake SD root in your temp folder and writes nothing. See [`examples/`](examples/).

### Execution policy
If PowerShell blocks the script, the launcher already passes `-ExecutionPolicy Bypass`.
To run a script manually under a restrictive policy:
```powershell
pwsh -ExecutionPolicy Bypass -File ./src/Start-PocketPrep.ps1
```

---

## How to prepare an SD card (walkthrough)

1. Format your microSD as **exFAT** (recommended) or **FAT32** using Windows. exFAT
   avoids FAT32's 4 GB file-size limit, which some cores need.
2. Insert the card and run the wizard.
3. Select your card from the list (double-check the **drive letter, label and size**).
4. Let it install firmware (or pick a file you downloaded yourself).
5. Let it create the folder structure.
6. For each system you care about, point it at your ROM folder.
7. Review the summary, eject the card, and you're ready for the Pocket.

## How firmware installation works

Firmware details live in [`manifests/firmware.json`](manifests/firmware.json) — version,
official URL, filename, **MD5**, and size — so updates need only a JSON edit (see
[docs/manifests.md](docs/manifests.md)). The installer:

- downloads **only from official analogue.co hosts** (other hosts are rejected),
- **verifies the MD5 and size before placing the file**, refusing to install on mismatch,
- places a single `.bin` at the **root** of the card (what the Pocket expects), and
- in **offline mode** copies a firmware file you already downloaded (verified if a checksum is known).

Shipped manifest: **Pocket firmware 2.5** (2025-03-18),
MD5 `42cd214fd21111f60390167ce8cf1ff9`. Source:
<https://www.analogue.co/support/pocket/firmware>.

## How ROM import works

Systems are defined in [`manifests/systems.json`](manifests/systems.json) (data-driven,
editable without code). For each system the wizard:

- asks whether you want to configure it,
- asks for a source folder and validates it,
- matches only the system's ROM extensions and reports the count,
- copies into `Assets/<platform-id>/common/` on the card (the openFPGA convention),
- skips files that already exist unless you choose to overwrite, and
- never copies BIOS files unless you explicitly opt in.

> **Important:** openFPGA **platform-ids are defined by each core, not standardised by
> Analogue.** The manifest uses the ids of common community cores; if you use a
> different core, confirm its platform-id and edit the manifest. See
> [docs/manifests.md](docs/manifests.md).

## How to use test mode

Point the whole workflow at an ordinary folder instead of a card:
```powershell
pwsh ./src/Start-PocketPrep.ps1 -TestMode            # writes into %TEMP%\PocketSDTest
pwsh ./src/Start-PocketPrep.ps1 -TestMode -Root D:\PocketSDTest
```
Run the automated tests (no card, no real ROMs needed):
```powershell
pwsh ./scripts/Run-Tests.ps1
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| "No removable drives detected" | Re-seat the card; some readers present as fixed disks — use `-AllowAdvancedOverride` *carefully*, or use `-TestMode`. |
| Filesystem reported "not acceptable" | Format the card as exFAT (or FAT32) in Windows, then re-run. The tool won't format for you. |
| Firmware "MD5 mismatch" | The download was corrupted or the manifest is stale. Re-run; if it persists, update `manifests/firmware.json`. |
| Script won't run (policy) | Use the `PocketPrep.cmd` launcher or `-ExecutionPolicy Bypass`. |
| `pwsh` not found | Install PowerShell 7 from <https://aka.ms/powershell>. |

More in [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Known limitations

- No automatic core installation yet ([#13](https://github.com/korkibucek/analouge-pocket-sdcard-prepper/issues/13)).
- Live drive detection is Windows-only.
- Platform-ids may need per-core adjustment (see above).
- No GUI in this version (CLI wizard only).

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design and data flow
- [docs/safety-model.md](docs/safety-model.md) — exactly how destructive actions are prevented
- [docs/manifests.md](docs/manifests.md) — editing firmware/system manifests
- [docs/testing.md](docs/testing.md) — test mode and the Pester suite
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — contributing / dev setup
- [docs/ROADMAP.md](docs/ROADMAP.md) — what's next

## Licence

No licence has been chosen yet, so default copyright applies. If you intend this to be
open source, add a `LICENSE` file (e.g. MIT). Tracked as a follow-up.
