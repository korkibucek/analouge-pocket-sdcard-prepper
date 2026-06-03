# Safety model

This tool touches storage devices, so it is designed so that **the worst realistic
outcome is "files copied to the wrong folder"** — never data loss.

## Principles

1. **No destructive operations exist in the codebase.** There is no format, wipe,
   delete-existing, or repartition path. The only filesystem mutations are:
   - `New-Item -ItemType Directory` (create folders), and
   - `Copy-Item` (copy files in).
   Nothing removes user content. (The tool removes only its own temporary download
   folder.)
2. **Removable-only by default.** `Get-PocketRemovableDrive` returns removable media
   only; fixed disks appear only with `-IncludeFixed` (advanced).
3. **System volumes can never be targeted (any OS).** `Test-PocketDriveSafety` rejects
   the Windows `%SystemDrive%` (e.g. `C:`) and, on Linux/macOS, protected mountpoints
   (`/`, `/boot`, `/usr`, `/home`, `/System`, the volume holding `$HOME`, etc.) — even
   when the advanced override is supplied. Volumes are identified by `RootPath`
   (mountpoint on Linux/macOS, drive root on Windows).
4. **Fixed/large disks require a deliberate override.** A non-removable drive is
   refused unless `-AllowAdvancedOverride` is explicitly passed, and a non-removable
   drive larger than 512 GB is additionally flagged as a likely internal/backup disk.
5. **Non-empty cards are surfaced, not silently used.** `Test-PocketCardEmpty` lists
   existing top-level content (ignoring OS housekeeping like
   `System Volume Information`). The wizard requires explicit confirmation to proceed,
   and existing files are left untouched.
6. **Firmware is verified before placement.** Downloads are MD5- and size-checked
   against the manifest and are refused on mismatch. Downloads are restricted to
   official `analogue.co` hosts.
7. **Existing files are never overwritten by default.** ROM copy skips files that
   already exist unless the user opts into `-Overwrite`.
8. **Everything is logged**, and **dry-run** is available end-to-end.

## The safety verdict

`Test-PocketDriveSafety` returns:

| Field | Meaning |
|---|---|
| `Safe` | Whether the wizard may proceed |
| `IsSystemDrive` | True if this is the OS drive (always unsafe) |
| `RequiresOverride` | True if only an explicit advanced override allows it |
| `OverrideApplied` | Whether the override was supplied |
| `Reasons` | Human-readable explanations shown to the user |

Decision order: no drive letter → unsafe; system drive → unsafe (non-overridable);
non-removable → needs override (and flagged if large); otherwise safe.

## The one destructive feature: `Clear-PocketCard` (opt-in)

`Clear-PocketCard` is the **only** function that deletes user data. It exists so a used
card can be re-prepped, and it is gated so the worst realistic outcome requires the user
to actively defeat several safeguards:

1. **Removable + non-system only.** The target must be a *detected removable volume* and
   must pass `Test-PocketDriveSafety`. A fixed disk needs the explicit advanced override;
   the system/protected volumes are never allowed. If the path isn't a detected removable
   volume, it refuses (it cannot verify safety).
2. **Typed confirmation.** `-ConfirmToken` must exactly match the volume label or the
   resolved root path — a deliberate, typed action.
3. **Contents only.** It deletes the contents of the root, never the root itself, and
   skips OS-managed entries (e.g. `System Volume Information`).
4. **Dry-run.** `-DryRun` lists exactly what would be removed and deletes nothing; the
   CLI always shows a dry-run preview before asking for confirmation.
5. **Logged.** Every removal is logged at WARN.

It is **never** invoked by default. The CLI exposes it only via the explicit
`-CleanFirst` flag (and still requires the typed confirmation). It is intentionally
**not** exposed over the web API, to avoid a destructive operation behind an HTTP
endpoint. Always back up saves first (`Backup-PocketSaves`); there is no undo.

## Privileges

The normal workflow does **not** require Administrator. If a future feature needs
elevation (e.g. low-level disk inspection), it must explain exactly why before
requesting it.
