# Security policy

## Reporting a vulnerability
Please report security issues **privately** rather than opening a public issue:

- Use GitHub's **"Report a vulnerability"** (Security tab → Advisories) on this repository, or
- Email the maintainer (see the repository owner's profile).

Include what you found, how to reproduce it, and the impact. We'll acknowledge and work on
a fix; please allow reasonable time before any public disclosure.

## Scope / threat model
This is a **local** desktop tool. It copies files to a removable SD card and, optionally,
downloads firmware/cores from official sources. The detailed threat model — the
localhost-only, token-secured web server; safe, non-destructive file operations; download
verification — is documented in [docs/SECURITY.md](../docs/SECURITY.md) and
[docs/safety-model.md](../docs/safety-model.md).

Particularly relevant areas: the local HTTP API (auth token, Host/Origin checks),
firmware/core download integrity (MD5/SHA-256, official hosts only), and the guarded
`Clear-PocketCard` destructive path.

## Supported versions
The latest release is supported. Fixes are shipped in a new release.
