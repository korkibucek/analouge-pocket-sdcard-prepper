# Windows: first run

This is a free, open-source hobby project, and Windows releases are **not code-signed**.
That's a deliberate choice — code-signing certificates cost money and require an identity/
org process this project isn't going to do right now. So Windows adds a little friction the
first time you run a freshly-downloaded copy. Here's the whole path.

The tool only ever copies files to your SD card — it never formats or deletes.

## 1. Download from the official Releases page
Get the release from
[GitHub Releases](https://github.com/korkibucek/analouge-pocket-sdcard-prepper/releases).
Don't run copies from anywhere else.

## 2. Verify the download (recommended)
Each release includes a `SHA256SUMS` file. Check your download matches it. In PowerShell,
from the folder where you saved the files:

```powershell
# Show the hash of what you downloaded
Get-FileHash .\AnaloguePocketSDCardPrepper-*.zip -Algorithm SHA256

# Compare against the published list (the line for your file should match)
Get-Content .\SHA256SUMS
```
The hash from `Get-FileHash` should appear in `SHA256SUMS` next to your file's name. If it
doesn't match, don't run it — re-download.

## 3. Install PowerShell 7
The tool needs PowerShell 7 (`pwsh`), which is separate from the blue "Windows PowerShell"
5.1 that ships with Windows.

- Easiest: `winget install Microsoft.PowerShell`, or
- Download from <https://aka.ms/powershell>.

## 4. Unblock the files (Mark of the Web)
Files downloaded from the internet are tagged "blocked". Either:

- **One file:** right-click `PocketPrep.cmd` → **Properties** → tick **Unblock** → **OK**.
- **Everything you extracted (recommended for the zip):** open PowerShell 7 in the
  extracted folder and run:
  ```powershell
  Get-ChildItem -Recurse | Unblock-File
  ```

## 5. Start it
Double-click **`PocketPrep.cmd`** — it opens the web UI in your browser (or
`PocketPrep.cmd cli` for the text wizard).

## 6. If SmartScreen appears
You may see "Windows protected your PC" because the app isn't signed. Click **More info** →
**Run anyway**.

## Execution policy
`PocketPrep.cmd` already runs PowerShell with `-ExecutionPolicy Bypass` for that one
process, so you don't need to change your system execution policy. To run a `.ps1` directly
under a restrictive policy:
```powershell
pwsh -ExecutionPolicy Bypass -File .\src\Start-PocketPrepWeb.ps1
```

## About signing (and what doesn't help)
A few things people suggest that don't actually solve this:

- **Let's Encrypt** issues TLS/HTTPS certificates for websites. It does **not** issue
  Authenticode code-signing certificates, so it can't remove the SmartScreen/Unblock prompt.
- **A self-signed certificate** only helps if you manually install it into your machine's
  Trusted Publishers store. That's fine for local development, but it does nothing for
  anyone else, so the project doesn't ship one.

The supported way to trust a release is the steps above: download from the official Releases
page, verify the SHA256 checksum, unblock, run.

If the project ever gets popular enough to justify it, a free OSS-friendly signing route
(e.g. [SignPath Foundation](https://signpath.org/)) could be adopted — there's nothing to
do about that today.
