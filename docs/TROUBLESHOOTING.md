# Troubleshooting

## "No removable drives detected"
Some USB / built-in card readers expose the card as a **fixed** disk. The tool now
**detects this** and, when no removable drive is found, lists fixed drives that look like
an SD card (a FAT32/exFAT, card-sized volume) and tells you to enable advanced mode:
- CLI: re-run with `-AllowAdvancedOverride` and pick the highlighted drive (the system
  drive is still blocked; verify the size/label match your card first).
- Web UI: tick the **Advanced** checkbox and select the highlighted candidate.
- Or try a different reader / re-seat the card, or use `-TestMode` to work against a folder.

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

## Core download fails / "rate limit"
Core downloads come from the author's GitHub releases. GitHub's unauthenticated API allows
~60 requests/hour; if you hit it you'll see a clear rate-limit message — wait an hour or set
`GITHUB_TOKEN` to raise the limit. Offline/404 errors are reported plainly. You can always
download a core zip from its homepage and install it via the offline option.

## "Update all" found nothing / a core won't update
Update detection compares the installed core's `core.json` version to its latest GitHub
release. If a core wasn't installed by this tool (no `core.json`) or isn't in the manifest,
it won't be checked. Reinstall the core to refresh it.

## Backup/restore didn't copy anything
Backup only copies the card's `Saves/` (and `Memories/` if you opt in). If those folders
are empty there's nothing to back up. Restore skips files that already exist unless you
choose overwrite.

## The web page looks frozen during a download
The local server is single-threaded; while it downloads firmware/a core (up to ~a minute)
the page is intentionally unresponsive and shows a "please wait" message. Downloads have a
timeout, so it won't hang forever. Use the CLI (`--cli`) for a fully headless flow.

## Web UI won't load / "Could not reach the local server"
Make sure you opened the URL the launcher printed (it's `127.0.0.1` only). The page carries
the session token automatically. If you left it idle for an hour it auto-shut-down — re-run
the launcher.

## Where are the logs?
By default in `%TEMP%\PocketPrepLogs\pocketprep-<timestamp>.log` (Windows) or
`$TMPDIR/PocketPrepLogs` (Linux/macOS), and optionally copied to the SD card root at the
end of a real run. Logs record actions (firmware/folder/ROM/core operations) with
timestamps; they contain **local file paths but no secrets**, and are never uploaded.
The tool keeps the most recent ~20 logs and prunes older ones automatically.

## ROMs went to a folder my core doesn't read
The core's **platform-id** likely differs from the manifest. Open the core, check its
platform id, and edit `platformId` in `manifests/systems.json`. See
[manifests.md](manifests.md).
