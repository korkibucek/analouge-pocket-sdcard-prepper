# Real-device UAT checklist (release gate)

This is the **manual acceptance test** that must pass before a public release (issue #47).
Nothing in CI can substitute for it: every automated test runs against a fake SD root or
injected drive data, so detection, firmware placement, the folder/ROM layout, and "does a
Pocket actually boot" are **only** proven here.

Run the whole checklist on each OS, then have at least one prepared card boot a real
Analogue Pocket. Record outcomes in `docs/UAT-RESULTS.md` (copy the results table below).

## Prerequisites
- A real Analogue Pocket (ideally one that still needs its first firmware update).
- 2+ microSD cards of different sizes/brands (e.g. 64 GB + 256 GB), plus at least two
  **different readers** (a built-in slot reader **and** a USB reader — these often report
  differently; see #18).
- A few legally-obtained ROMs you own, for a couple of systems (e.g. Game Boy + NES).
- PowerShell 7 installed on each test machine.

> Safety: the tool only copies files; it never formats. Still, double-check the selected
> drive's letter/mountpoint/label/size before each run.

## Per-OS run (repeat on Windows 10/11, Ubuntu, a Fedora/RHEL-family distro, macOS)

### A. Detection & safety
1. Insert a blank, exFAT-formatted card. Launch the tool (web UI **and** CLI at least once).
2. Confirm the card appears with the **correct** drive letter/mountpoint, label, filesystem,
   total size, free space, and is flagged **removable**.
3. Confirm internal/system disks are **not** offered (and that selecting one is refused).
4. Repeat detection with the **other reader**; note whether the card shows as removable or
   fixed (record reader make/model). If it shows as fixed, exercise the advanced override
   and confirm the warnings are clear.

### B. Filesystem / emptiness
5. Confirm exFAT is reported acceptable. Try a FAT32 card; confirm the 4 GB caveat is shown.
   (Optional) try an NTFS card; confirm it's reported not-acceptable with remediation.
6. Put a file on the card; confirm the non-empty warning + required confirmation.

### C. Firmware
7. Install firmware via **download** (MD5-verified) and confirm `OnCardVerified`/success.
8. Install firmware via **offline** mode (a file you downloaded from analogue.co).
9. Confirm the firmware `.bin` is at the **root** with the expected name, and that no other
   firmware `.bin` remains (heed the warning if one does).

### D. Folder structure
10. Confirm `Assets, Cores, Saves, Settings, System, Memories, Presets, "GB Studio",
    Platforms` exist at the root; re-run and confirm idempotency (no errors/loss).

### E. Cores
11. Download-install at least one core (e.g. agg23.NES). Confirm `Cores/<id>/` plus
    `Platforms/` and `Assets/` content. Run the installed-core inventory and update check.

### F. ROM import
12. Import ROMs for 1–2 systems from a real folder. Confirm counts, that files land in
    `Assets/<platformId>/common`, and that the free-space preflight refuses an oversized
    selection (try copying more than fits on a small card).
13. Confirm BIOS files are **not** copied unless explicitly chosen.

### G. Backup / clean
14. (If the card has saves) back up `Saves/`, then restore to a fresh card; confirm files.
15. (Optional, **destructive**) `-CleanFirst` on a used card: confirm the dry-run preview,
    the typed-token requirement, and that only the card's contents are removed.

### H. Finish & boot
16. Review the summary/log; confirm the safe-eject prompt. Eject the card cleanly.
17. **Insert the card into a real Analogue Pocket and power on.** Confirm:
    - firmware update applies (progress bar, reboot), and
    - at least one installed core + imported ROM loads and runs.

## Results table (copy to docs/UAT-RESULTS.md)

| OS / version | Reader (make/model) | Card (brand/size/fs) | A–G result | Pocket boot + firmware + core/ROM | Tester | Date | Notes / issues filed |
|---|---|---|---|---|---|---|---|
| Windows 11 | | | | | | | |
| Ubuntu 24.04 | | | | | | | |
| Fedora/RHEL | | | | | | | |
| macOS | | | | | | | |

## Pass criteria (release gate)
- A–H complete on Windows, Linux, and macOS with at least one card each.
- At least one **real Pocket boots** from a tool-prepared card with firmware applied and a
  core+ROM running.
- Any discrepancy is filed as a follow-up issue and triaged before release.
