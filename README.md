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
7. Optionally installs **openFPGA cores** from a curated set — either by downloading the
   core's official GitHub release or from a `.zip` you already have — extracted safely
   (zip-slip-protected, non-destructive).
8. Walks you through **ROM import per system**, copying your ROMs into the correct folders.
9. Prints a **summary** and writes a **log** (locally, and optionally to the card).

## What it does NOT do

- It installs only a **curated set** of openFPGA cores ([`manifests/cores.json`](manifests/cores.json)), not the entire community inventory. Add more by editing the manifest, or install any core manually. Cores remain under their authors' licences; this tool does not bundle or relicense them.
- It does **not** format cards. If the filesystem is wrong, it tells you how to fix it.
- It does **not** ship a graphical UI in this version — it's a clear interactive wizard (GUI is on the roadmap, [issue ...]).

---

## Requirements

- **Windows 10/11, Linux (Ubuntu/Debian, Fedora/RHEL/AlmaLinux), or macOS.**
- **PowerShell 7.2+** (`pwsh`). Install from <https://aka.ms/powershell> (Windows),
  your distro's package/Microsoft apt repo (Linux), or `brew install --cask powershell` (macOS).
- A modern browser for the web UI: **Chrome/Edge 80+, Firefox 74+, or Safari 13.1+**
  (older browsers get a clear "please update" message instead of a blank page).
- **No Administrator/root rights needed** for the normal copy workflow. (Reading drive
  metadata and copying files to a removable card do not require elevation.)

---

## Supported platforms

| OS | Drive detection | How to run |
|---|---|---|
| Windows 10/11 | Windows Storage APIs | `PocketPrep.cmd` (web UI) |
| Linux (Ubuntu/Debian, Fedora/RHEL/AlmaLinux) | `lsblk` | `pocketprep` / `scripts/pocketprep.sh` |
| macOS | `system_profiler` | `scripts/pocketprep.sh` |

All three need **PowerShell 7.2+** (`pwsh`). The engine and tests are cross-platform; CI
runs on Windows, Linux, and macOS.

## How to run

The default front-end is a **local web UI** (a wizard in your browser). A text **CLI
wizard** is also available with `--cli` (Linux/macOS) or `PocketPrep.cmd cli` (Windows).

### Windows
Double-click **`PocketPrep.cmd`** — it starts the web UI in your browser. For the text
wizard: `PocketPrep.cmd cli`.

> **First time on Windows?** This build isn't code-signed yet, so Windows adds some
> friction (PowerShell 7 install, "Unblock", possible SmartScreen prompt). The
> step-by-step [Windows first-run guide](docs/WINDOWS-FIRST-RUN.md) walks through it.

### Linux / macOS
```bash
./scripts/pocketprep.sh                 # web UI (opens your browser)
./scripts/pocketprep.sh --cli           # text wizard
./scripts/pocketprep.sh --test --dry-run
```
Install PowerShell 7 first: Ubuntu/Debian via Microsoft's apt repo
(<https://learn.microsoft.com/powershell>), Fedora/RHEL `sudo dnf install -y powershell`,
macOS `brew install --cask powershell`.

### Packages
Build a native package (output in `dist/`):
```bash
bash scripts/Build-Deb.sh    # .deb for Debian/Ubuntu (needs dpkg-deb)
bash scripts/Build-Rpm.sh    # .rpm for Fedora/RHEL/AlmaLinux (needs rpmbuild)
```
Both install a `pocketprep` command and a desktop entry.

> **PowerShell 7 prerequisite:** `pwsh` is the runtime but it is **not** in the default
> Debian/Ubuntu/Fedora repositories, so the package declares it as a *weak* dependency
> (`Recommends`) — the package installs cleanly even if `pwsh` is absent, and the
> post-install message + the `pocketprep` launcher tell you how to install it. Install
> PowerShell 7 first (or when prompted): Ubuntu/Debian via Microsoft's apt repo
> (<https://learn.microsoft.com/powershell>), Fedora/RHEL `sudo dnf install -y powershell`.

### From source
```powershell
pwsh ./src/Start-PocketPrepWeb.ps1      # web UI
pwsh ./src/Start-PocketPrep.ps1         # CLI wizard
```

### Try it safely with no SD card (test mode)
```bash
./scripts/pocketprep.sh --test --dry-run            # web UI, writes nothing
pwsh ./src/Start-PocketPrep.ps1 -TestMode -DryRun   # CLI
```
This uses a fake SD root in your temp folder. See [`examples/`](examples/).

### Web UI security
The server binds to **127.0.0.1 only** and requires a per-session token (printed in the
console and injected into the page) on every API call, with Host/Origin checks. It is not
reachable from other machines. See [docs/safety-model.md](docs/safety-model.md).

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

## How core installation works

Cores are defined in [`manifests/cores.json`](manifests/cores.json) with their
`Author.CoreName` identifier and GitHub repository. For each core you choose, the tool:

- **downloads** the core's latest official GitHub **release** zip (hosts restricted to
  GitHub), **or** uses a **`.zip` you already downloaded** from the core's homepage; then
- validates the zip is a real openFPGA package and **rejects unsafe paths** (zip-slip), then
- extracts only the recognised openFPGA folders (`Assets`, `Cores`, `Platforms`,
  `Presets`, `Settings`) onto the card, **skipping files that already exist** unless you
  overwrite.

Core identifiers/repos come from the community
[openFPGA Cores Inventory](https://github.com/joshcampbell191/openfpga-cores-inventory).
BIOS files are never installed automatically.

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

Highlights (full list in [docs/KNOWN-LIMITATIONS.md](docs/KNOWN-LIMITATIONS.md)):

- Core installation covers a curated set, not the full community inventory (extend via the manifest).
- Live drive detection works on Windows/Linux/macOS but is hardware-verified via manual UAT, not CI.
- Platform-ids may need per-core adjustment (see above).
- Neo Geo / arcade / CD systems are experimental (BIOS/romset handling not fully managed).
- Windows builds aren't code-signed yet (expect SmartScreen/Unblock; see the first-run guide).

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design and data flow
- [docs/safety-model.md](docs/safety-model.md) — exactly how destructive actions are prevented
- [docs/SECURITY.md](docs/SECURITY.md) — web server threat model + engine security
- [docs/manifests.md](docs/manifests.md) — editing firmware/system manifests
- [docs/testing.md](docs/testing.md) — test mode and the Pester suite
- [docs/UAT.md](docs/UAT.md) — real-device acceptance checklist (release gate)
- [docs/RELEASE.md](docs/RELEASE.md) — release checklist + rollback
- [docs/KNOWN-LIMITATIONS.md](docs/KNOWN-LIMITATIONS.md) — what it does not do / caveats
- [docs/PERFORMANCE.md](docs/PERFORMANCE.md) — large-library copy benchmark
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — common problems
- [docs/WINDOWS-FIRST-RUN.md](docs/WINDOWS-FIRST-RUN.md) — unblock/SmartScreen on Windows
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — contributing / dev setup
- [docs/ROADMAP.md](docs/ROADMAP.md) — what's next

## Licence

[MIT](LICENSE). You may use, modify, and redistribute it freely; it comes with no
warranty. (MIT was chosen as a sensible permissive default for a community tool — open
a PR if you'd prefer a different licence.)
