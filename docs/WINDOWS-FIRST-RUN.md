# Windows: first run (unsigned build)

> This build is **not code-signed yet** (tracked in the signing issue). Windows therefore
> adds friction the first time you run a freshly-downloaded copy. This page walks through
> it. None of these steps reduce your security beyond running this specific tool, and the
> tool only ever copies files to your SD card — it never formats or deletes.

## 1. Install PowerShell 7
The tool needs PowerShell 7 (`pwsh`), which is separate from the blue "Windows
PowerShell" 5.1 that ships with Windows.

- Easiest: open a terminal and run `winget install Microsoft.PowerShell`, or
- Download from <https://aka.ms/powershell>.

## 2. Unblock the downloaded files (Mark of the Web)
Files downloaded from the internet are tagged "blocked". Either:

**Option A — File Explorer (one file):** right-click `PocketPrep.cmd` → **Properties** →
tick **Unblock** at the bottom → **OK**.

**Option B — unblock everything you extracted (recommended for the zip):** open
PowerShell 7 in the extracted folder and run:
```powershell
Get-ChildItem -Recurse | Unblock-File
```

## 3. Start it
Double-click **`PocketPrep.cmd`**. It opens the web UI in your browser (or use
`PocketPrep.cmd cli` for the text wizard).

## 4. If Microsoft Defender SmartScreen appears
You may see "Windows protected your PC" because the app isn't signed. Click
**More info** → **Run anyway**. (This appears only until the project ships a signed build.)

## Why these steps exist
- **PowerShell 7** isn't preinstalled on Windows.
- **Mark-of-the-Web / SmartScreen** are Windows' protections for unsigned, internet-sourced
  executables. A code-signing certificate would remove them; that work is tracked
  separately. Until then, the steps above are the standard, safe way to run an unsigned
  open-source tool you trust.

## Execution policy
The `PocketPrep.cmd` launcher already runs PowerShell with `-ExecutionPolicy Bypass` for
that single process, so you do **not** need to change your system execution policy. If you
run a `.ps1` directly under a restrictive policy, use:
```powershell
pwsh -ExecutionPolicy Bypass -File .\src\Start-PocketPrepWeb.ps1
```
