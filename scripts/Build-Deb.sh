#!/usr/bin/env bash
# Builds a .deb for Debian/Ubuntu. Payload installs to /usr/lib/pocketprep with a
# /usr/bin/pocketprep launcher. Declares a dependency on PowerShell 7.
# Requires: dpkg-deb (and usually fakeroot). No root needed to build.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO/dist}"
VERSION="$(grep -oP "ModuleVersion\s*=\s*'\K[0-9.]+" "$REPO/src/PocketPrep/PocketPrep.psd1")"

command -v dpkg-deb >/dev/null || { echo "dpkg-deb not found (install dpkg-dev)." >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
PKG="$STAGE/pocketprep"
APP="$PKG/usr/lib/pocketprep"

mkdir -p "$PKG/DEBIAN" "$APP" "$PKG/usr/bin" "$PKG/usr/share/applications" "$PKG/usr/share/doc/pocketprep"
cp -r "$REPO/src" "$REPO/manifests" "$REPO/scripts" "$APP/"
cp "$REPO/README.md" "$REPO/CHANGELOG.md" "$REPO/LICENSE" "$PKG/usr/share/doc/pocketprep/" 2>/dev/null || true
cp "$REPO/packaging/pocketprep.desktop" "$PKG/usr/share/applications/"

cat > "$PKG/usr/bin/pocketprep" <<'EOF'
#!/usr/bin/env bash
exec /usr/lib/pocketprep/scripts/pocketprep.sh "$@"
EOF
chmod 0755 "$PKG/usr/bin/pocketprep" "$APP/scripts/pocketprep.sh"

cat > "$PKG/DEBIAN/control" <<EOF
Package: pocketprep
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: powershell
Maintainer: korkibucek <robert@morgan.vg>
Homepage: https://github.com/korkibucek/analouge-pocket-sdcard-prepper
Description: Analogue Pocket SD Card Prepper
 Prepare an SD card for an Analogue Pocket before it arrives: install firmware,
 create the openFPGA folder structure, optionally install cores, and copy your
 own ROMs. Copies files only; never formats or deletes. Provides a local web UI
 and a CLI wizard. Not affiliated with Analogue.
EOF

mkdir -p "$OUT"
DEB="$OUT/pocketprep_${VERSION}_all.deb"
if command -v fakeroot >/dev/null; then fakeroot dpkg-deb --build "$PKG" "$DEB"; else dpkg-deb --build "$PKG" "$DEB"; fi
echo "Built: $DEB"
