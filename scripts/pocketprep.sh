#!/usr/bin/env bash
# Analogue Pocket SD Card Prepper launcher for Linux and macOS.
# Default: starts the local web UI. Use --cli for the text wizard.
# Requires PowerShell 7 (pwsh). No root required for the normal workflow.
#
# Flags (translated to the underlying PowerShell parameters):
#   --cli            run the text wizard instead of the web UI
#   --test           use a test folder instead of a real SD card
#   --dry-run        plan only; write nothing
#   --no-browser     do not auto-open the browser (web mode)
#   --include-fixed  also list non-removable drives (advanced)
#   --port N         web server port
#   --root PATH      target root / fake SD root
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/../src" ]; then ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [ -d "$SCRIPT_DIR/src" ]; then ROOT="$SCRIPT_DIR"
else ROOT="$SCRIPT_DIR/.."; fi

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell 7 (pwsh) was not found." >&2
  echo "  Ubuntu/Debian: see https://learn.microsoft.com/powershell (apt)" >&2
  echo "  Fedora/RHEL:   sudo dnf install -y powershell" >&2
  echo "  macOS:         brew install --cask powershell" >&2
  exit 1
fi

MODE="web"
PS_ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cli)           MODE="cli" ;;
    --test|--test-mode) PS_ARGS+=("-TestMode") ;;
    --dry-run)       PS_ARGS+=("-DryRun") ;;
    --no-browser)    PS_ARGS+=("-NoBrowser") ;;
    --include-fixed) PS_ARGS+=("-IncludeFixed") ;;
    --port)          shift; PS_ARGS+=("-Port" "$1") ;;
    --root)          shift; PS_ARGS+=("-Root" "$1") ;;
    *)               PS_ARGS+=("$1") ;;
  esac
  shift
done

if [ "$MODE" = "cli" ]; then
  exec pwsh -NoProfile -File "$ROOT/src/Start-PocketPrep.ps1" "${PS_ARGS[@]}"
else
  exec pwsh -NoProfile -File "$ROOT/src/Start-PocketPrepWeb.ps1" "${PS_ARGS[@]}"
fi
