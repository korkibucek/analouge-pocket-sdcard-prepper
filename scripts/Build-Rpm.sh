#!/usr/bin/env bash
# Builds an .rpm for Fedora/RHEL/AlmaLinux. Same payload layout as the .deb.
# Requires: rpmbuild (package 'rpm-build'). No root needed to build.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO/dist}"
VERSION="$(grep -oP "ModuleVersion\s*=\s*'\K[0-9.]+" "$REPO/src/PocketPrep/PocketPrep.psd1")"

if ! command -v rpmbuild >/dev/null; then
  echo "rpmbuild not found. Install it first:" >&2
  echo "  Fedora/RHEL/AlmaLinux: sudo dnf install -y rpm-build" >&2
  exit 1
fi

TOP="$(mktemp -d)"; trap 'rm -rf "$TOP"' EXIT
mkdir -p "$TOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
NAME="pocketprep-$VERSION"
SRC="$TOP/SOURCES/$NAME"
mkdir -p "$SRC"
cp -r "$REPO/src" "$REPO/manifests" "$REPO/scripts" "$SRC/"
cp "$REPO/README.md" "$REPO/CHANGELOG.md" "$REPO/LICENSE" "$SRC/" 2>/dev/null || true
cp "$REPO/packaging/pocketprep.desktop" "$SRC/"
( cd "$TOP/SOURCES" && tar czf "$NAME.tar.gz" "$NAME" )

cat > "$TOP/SPECS/pocketprep.spec" <<EOF
Name:           pocketprep
Version:        $VERSION
Release:        1%{?dist}
Summary:        Analogue Pocket SD Card Prepper
License:        MIT
URL:            https://github.com/korkibucek/analouge-pocket-sdcard-prepper
BuildArch:      noarch
Requires:       powershell
Source0:        $NAME.tar.gz

%description
Prepare an SD card for an Analogue Pocket: firmware, openFPGA folder structure,
optional cores, and your own ROMs. Copies files only; never formats or deletes.
Provides a local web UI and a CLI wizard. Not affiliated with Analogue.

%prep
%setup -q -n $NAME

%install
mkdir -p %{buildroot}/usr/lib/pocketprep %{buildroot}/usr/bin %{buildroot}/usr/share/applications
cp -r src manifests scripts %{buildroot}/usr/lib/pocketprep/
install -m 0644 pocketprep.desktop %{buildroot}/usr/share/applications/pocketprep.desktop
printf '#!/usr/bin/env bash\nexec /usr/lib/pocketprep/scripts/pocketprep.sh "\$@"\n' > %{buildroot}/usr/bin/pocketprep
chmod 0755 %{buildroot}/usr/bin/pocketprep %{buildroot}/usr/lib/pocketprep/scripts/pocketprep.sh

%files
/usr/lib/pocketprep
/usr/bin/pocketprep
/usr/share/applications/pocketprep.desktop

%changelog
* Tue Jun 02 2026 korkibucek <robert@morgan.vg> - $VERSION-1
- Cross-platform release with local web UI.
EOF

rpmbuild --define "_topdir $TOP" -bb "$TOP/SPECS/pocketprep.spec"
mkdir -p "$OUT"
find "$TOP/RPMS" -name '*.rpm' -exec cp {} "$OUT/" \;
echo "Built RPM(s) in: $OUT"
