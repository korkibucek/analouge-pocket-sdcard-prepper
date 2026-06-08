# Security model

This tool copies files and can download firmware/cores, so it is built to be safe by
default. There are two surfaces: the **engine** (file operations) and the **local web
server**.

## Engine / file operations
See [safety-model.md](safety-model.md) for the full picture. In short:
- No destructive operations exist — only directory creation and file copy.
- The system volume can never be targeted (Windows system drive; Linux/macOS protected
  mountpoints); fixed disks require an explicit advanced override.
- Existing files are never overwritten unless you opt in; non-empty cards require
  confirmation.
- Firmware downloads are restricted to `analogue.co` hosts and verified by MD5+size
  before placement. Core downloads are restricted to GitHub hosts.
- Copyrighted system BIOS (e.g. the Neo Geo BIOS) is **never downloaded or supplied**. The
  tool only *detects* whether a BIOS you provided is present and guides you to add your own.
- Core zips are checked for path-traversal (zip-slip) entries and rejected; extraction
  is constrained to the SD root.

## Local web server threat model

`Start-PocketPrepServer` runs an HTTP server on your machine. The risk is that some
*other* program — a web page in your browser, another local app, or a remote host via
DNS-rebinding — could call the API and drive file operations. Mitigations:

| Threat | Mitigation |
|---|---|
| Remote network access | Binds to **`127.0.0.1` only** (never `0.0.0.0`). Not reachable off-host. |
| Other local apps / random web pages (CSRF) | Every `/api` call must send a **per-session token** (`X-PocketPrep-Token`). The token is random (128-bit), printed to the console, and injected into the served page. Requests without it get **401**. |
| DNS-rebinding / Host spoofing | The `Host` header must be loopback; a foreign `Host` is rejected (**403**), and HttpListener itself only routes loopback Hosts. |
| Cross-origin POSTs | If an `Origin` header is present it must be the loopback origin, else **403**. |
| Path traversal on static files | Static paths are stripped of `..` and confined to the bundled `web/` folder. |
| Folder picker (`POST /api/browse`) | Read-only: lists directory *names* only (never file contents), token-gated like every `/api` call. It exposes no more than the user can already do by typing a path, and the server only runs on their own machine. |
| Token leakage via URL | The browser is opened at the bare URL; the session token is only injected into the served page, not placed in the URL/query (so it can't leak via shell history or `Referer`). |
| Forgotten server left open | The server **auto-shuts down after an idle timeout** (default 1 hour, `-IdleTimeoutSeconds`, 0 to disable). |
| Information disclosure | Errors return a short message, never stack traces. No secrets are logged. Optional `-LogRequests` prints method/path/status (paths only, no secrets) for troubleshooting. |

What it deliberately does **not** do:
- No authentication beyond the local token (it is a single-user, local tool).
- No TLS (loopback only; traffic never leaves the machine).
- It does not require Administrator/root.

If you do not want any server at all, use the CLI wizard (`--cli` /
`Start-PocketPrep.ps1`), which uses the same engine with no network surface.

## Reporting
Open a GitHub issue (or a private advisory) for anything security-relevant.
