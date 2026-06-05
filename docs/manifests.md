# Manifests

All firmware and system data is JSON under `manifests/`, validated on load. You can
update these **without changing code**.

## firmware.json

```jsonc
{
  "latest": "2.5",
  "releases": [
    {
      "version": "2.5",
      "releaseDate": "2025-03-18",
      "url": "https://www.analogue.co/support/pocket/firmware/2.5/download",
      "fileName": "pocket_firmware_2_5.bin",
      "md5": "42cd214fd21111f60390167ce8cf1ff9",
      "sizeBytes": 54525952,
      "notes": "..."
    }
  ]
}
```

| Field | Notes |
|---|---|
| `latest` | Must equal one release's `version`. |
| `url` | **Must be an official analogue.co URL.** The installer rejects other hosts. The stable `analogue.co/.../download` link 308-redirects to `assets.analogue.co`. |
| `fileName` | Must end in `.bin`. This is the name written to the SD root. |
| `md5` | 32-hex; published on the firmware page. The download is verified against it. |
| `sizeBytes` | Used as a secondary check. |

### Updating to a new firmware

1. Open the official firmware page: <https://www.analogue.co/support/pocket/firmware>.
2. Note the version, date, file size and the published **MD5**.
3. Resolve the real download (the `/download` link redirects); the filename is in the
   final URL (e.g. `pocket_firmware_2_5.bin`).
4. Add a new entry to `releases` and set `latest`.
5. Run the tests: `pwsh ./scripts/Run-Tests.ps1`.

> URLs live here, not in code, **on purpose** — Analogue's download links and
> checksums change with each release, and hardcoding them would be brittle.

### Staleness detection (automated + at install time)

- A scheduled GitHub Actions workflow (`.github/workflows/firmware-check.yml`) runs
  monthly, compares `latest` against the official firmware page, and **opens an issue**
  when Analogue publishes a newer version — so the manifest gets refreshed promptly.
- At install time, `Test-PocketFirmwareManifestAge` flags a manifest whose newest
  release is older than ~9 months; the CLI and web UI then warn the user to check the
  official page and use offline mode if a newer firmware exists.

## systems.json

```jsonc
{
  "systems": [
    {
      "id": "gb",
      "displayName": "Game Boy",
      "manufacturer": "Nintendo",
      "platformId": "gb",
      "supportedExtensions": [".gb"],
      "requiresCore": true,
      "suggestedCore": "Spiritualized1997.GB",
      "biosRequired": false,
      "biosFiles": [],
      "notes": "ROMs go to Assets/gb/common."
    }
  ]
}
```

| Field | Notes |
|---|---|
| `id` | Unique, lowercase, used on the command line and in summaries. |
| `platformId` | The folder under `Assets/`. **Defined by the openFPGA core, not by Analogue.** |
| `supportedExtensions` | Each like `.gb`; matching is case-insensitive. |
| `requiresCore` | Informational — the matching openFPGA core must be installed separately. |
| `suggestedCore` | Informational `Author.CoreName` hint; this tool does not install cores. |
| `biosRequired` / `biosFiles` | BIOS is never copied automatically; opt-in only. |

ROM destination is computed as `Assets/<platformId>/common`.

### ⚠️ The platform-id caveat

Analogue's developer docs define the *structure* (`Assets/<platform>/common`) but the
*platform-id* is set by each core's platform definition. The shipped values match the
most widely used community cores at time of writing. **If you use a different core,
open it, check its platform id, and edit `platformId` here.** This is exactly why the
design is data-driven.

Once a core is installed, the tool can read the truth directly:
`Get-PocketInstalledCore` returns each installed core's declared `platform_ids` (from
`Cores/<id>/core.json`), and `Test-PocketPlatformIdInstalled` checks whether any
installed core provides a given platform id — so ROM destinations can be verified
against reality rather than only the manifest.

Sources:
- Folder structure: <https://www.analogue.co/developer/docs/directories-and-sd-folder-structure>
- Firmware + SD format: <https://www.analogue.co/support/resource/updating-firmware>

## cores.json

```jsonc
{
  "cores": [
    {
      "id": "nes",
      "identifier": "agg23.NES",         // also the folder created under Cores/
      "displayName": "NES (agg23)",
      "platformIds": ["nes"],
      "owner": "agg23",                   // GitHub owner/repo used to resolve the release zip
      "repo": "openfpga-NES",
      "homepage": "https://github.com/agg23/openfpga-NES",
      "biosRequired": false,
      "biosFiles": [],
      "notes": "..."
    }
  ]
}
```

| Field | Notes |
|---|---|
| `identifier` | `Author.CoreName`; the installer expects `Cores/<identifier>/` inside the zip. |
| `owner`/`repo` | GitHub coordinates. Download mode resolves the **latest release** (or a given `-Tag`) and picks its `.zip` asset via the GitHub API. We deliberately do **not** hardcode per-release asset URLs. |
| `homepage` | Where a user can download the zip themselves for offline install. |
| `biosRequired`/`biosFiles` | Informational; BIOS is never installed automatically. |

Adding a core: find its `identifier` and GitHub `owner`/`repo` in the
[openFPGA Cores Inventory](https://github.com/joshcampbell191/openfpga-cores-inventory),
add an entry, and run the tests. Download mode uses the unauthenticated GitHub API
(60 requests/hour) — offline mode has no such limit.

## Schemas

`manifests/schemas/*.schema.json` document the expected shape. The loaders perform
equivalent structural validation in PowerShell and fail fast with a clear message
naming the offending field.
