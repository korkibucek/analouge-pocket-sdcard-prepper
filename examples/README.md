# Examples

These files support **test mode** so you can exercise the whole tool without a real
SD card or any real ROMs.

- `fake-sd-source/` contains tiny placeholder files with retro ROM extensions
  (`.gb`, `.nes`). **They are not games** — just bytes so the copy logic has
  something to match. A `readme.txt` is included so you can see that non-matching
  files are correctly skipped.

## Try it

```powershell
# From the repo root. Creates a fake SD root in your temp folder, plans only.
pwsh ./src/Start-PocketPrep.ps1 -TestMode -DryRun
```

When the wizard asks about **Game Boy**, point it at
`examples/fake-sd-source/GameBoy` and you'll see it find 2 `.gb` files and skip the
`.txt`. Re-run without `-DryRun` to actually copy into the fake SD root
(`%TEMP%\PocketSDTest\Assets\gb\common`).
