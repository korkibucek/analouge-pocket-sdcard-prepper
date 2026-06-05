# Troubleshooting

## "No removable drives detected"
Some USB card readers expose the card as a **fixed** disk. Options:
- Try a different reader, or re-seat the card.
- Re-run with `-AllowAdvancedOverride` and select carefully (the system drive is still
  blocked). Verify the size/label match your card before proceeding.
- Use `-TestMode` to work against a folder instead.

## Filesystem reported "not acceptable"
The Pocket needs **FAT32 or exFAT**. Format the card in Windows (File Explorer →
right-click drive → Format, choose exFAT), then re-run. This tool never formats for you.

FAT32 is accepted but warns about the 4 GB per-file limit; prefer exFAT for large cores.

## Firmware "MD5 mismatch / validation failed"
The download was corrupted, or the manifest is out of date.
- Re-run to download again.
- If it persists, the published checksum may have changed — update
  `manifests/firmware.json` (see [manifests.md](manifests.md)).
- Or use **offline mode**: download the `.bin` yourself from
  <https://www.analogue.co/support/pocket/firmware> and point the wizard at it.

## "Refusing to download firmware from non-official host"
The manifest `url` must be an `analogue.co` address. Fix the manifest.

## Script won't run / execution policy error
Use the `PocketPrep.cmd` launcher, or:
```powershell
pwsh -ExecutionPolicy Bypass -File ./src/Start-PocketPrep.ps1
```

## `pwsh` is not recognised
Install PowerShell 7 from <https://aka.ms/powershell>. (Windows PowerShell 5.1 — the
blue one — is not supported; this tool targets `pwsh` 7.2+.)

## "Not enough free space on the card"
The tool now checks free space before writing firmware, ROMs, or cores, and refuses
rather than failing half-way and leaving a partly-written card. Free up space on the
card (or use a larger one) and retry. The ROM step also shows a pre-copy warning when a
selection won't fit.

## Where are the logs?
By default in `%TEMP%\PocketPrepLogs\pocketprep-<timestamp>.log`, and optionally copied
to the SD card root at the end of a real run.

## ROMs went to a folder my core doesn't read
The core's **platform-id** likely differs from the manifest. Open the core, check its
platform id, and edit `platformId` in `manifests/systems.json`. See
[manifests.md](manifests.md).
