#!/usr/bin/env bash
# Packages an already-built Linux bundle two ways:
#
#   darkmoon-v<VER>-linux-x64.tar.gz   portable — extract and run
#   darkmoon_<VER>_amd64.deb           installer — apt/dpkg, menu entry
#
# Run `flutter build linux --release` first; this only packages.
#
# The .deb covers Debian and Ubuntu derivatives only. Everyone else gets
# the tarball, which carries install.sh for the menu entry. That is an
# honest limit, not an oversight: one .deb cannot serve Fedora and Arch,
# and a 1.3GB payload makes "ship every format" a poor trade.
set -euo pipefail

cd "$(dirname "$0")/.."
VER="$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' pubspec.yaml)"
[ -n "$VER" ] || { echo "error: could not read version from pubspec.yaml" >&2; exit 1; }

BUNDLE="build/linux/x64/release/bundle"
[ -x "$BUNDLE/darkmoon" ] || {
  echo "error: no build at $BUNDLE — run 'flutter build linux --release' first." >&2
  exit 1
}

OUT="$(cd .. && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo "==> darkmoon $VER"

# ---------------------------------------------------------------- tarball
# Wrapped in a top-level darkmoon/ folder so extracting matches the Windows
# zip's layout and never scatters 1.3GB across the current directory.
echo "==> Portable tarball"
mkdir -p "$STAGE/tar"
cp -a "$BUNDLE" "$STAGE/tar/darkmoon"
TARBALL="$OUT/darkmoon-v${VER}-linux-x64.tar.gz"
rm -f "$TARBALL"
tar -czf "$TARBALL" -C "$STAGE/tar" darkmoon
echo "    $TARBALL  ($(du -h "$TARBALL" | cut -f1))"

# -------------------------------------------------------------------- deb
echo "==> Debian package"
ROOT="$STAGE/deb"
mkdir -p "$ROOT/DEBIAN" "$ROOT/opt/darkmoon" \
         "$ROOT/usr/share/applications" \
         "$ROOT/usr/share/icons/hicolor/256x256/apps"

cp -a "$BUNDLE/." "$ROOT/opt/darkmoon/"
# install.sh registers a menu entry per user; the package does that
# system-wide through its own .desktop, so shipping both would offer the
# user a second, redundant way to do what dpkg already did.
rm -f "$ROOT/opt/darkmoon/install.sh" "$ROOT/opt/darkmoon/uninstall.sh"

[ -f "$BUNDLE/data/icon.png" ] &&
  cp -f "$BUNDLE/data/icon.png" \
    "$ROOT/usr/share/icons/hicolor/256x256/apps/darkmoon.png"

# No %f, no MimeType — the application takes no file argument, so claiming
# to handle files would put it in "Open With" and then do nothing.
cat > "$ROOT/usr/share/applications/darkmoon.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=darkmoon
GenericName=RAW Photo Editor
Comment=Develop and edit RAW photographs
Exec=/opt/darkmoon/darkmoon
Icon=darkmoon
Terminal=false
Categories=Graphics;2DGraphics;RasterGraphics;Photography;
Keywords=photo;raw;editor;develop;
StartupWMClass=darkmoon
DESKTOP

# Depends deliberately lists only what the app links against and does not
# ship itself. The ONNX, LibRaw and WebGPU libraries are bundled in
# opt/darkmoon/lib, so they must NOT appear here.
INSTALLED_KB="$(du -sk "$ROOT/opt" | cut -f1)"
cat > "$ROOT/DEBIAN/control" <<CONTROL
Package: darkmoon
Version: ${VER}
Section: graphics
Priority: optional
Architecture: amd64
Depends: libgtk-3-0 (>= 3.22), libglib2.0-0, libstdc++6 (>= 4.8), zlib1g
Installed-Size: ${INSTALLED_KB}
Maintainer: Vini <viniciusfos1996@gmail.com>
Homepage: https://darkmoon.pt
Description: RAW photo editor
 darkmoon develops and edits RAW photographs, with GPU-accelerated
 rendering and optional AI-assisted denoise, detail restoration and
 colorization running locally.
CONTROL

cat > "$ROOT/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
fi
POSTINST
chmod 755 "$ROOT/DEBIAN/postinst"

DEB="$OUT/darkmoon_${VER}_amd64.deb"
rm -f "$DEB"
# --root-owner-group: files staged as the building user must land as
# root:root, or dpkg installs an app owned by a uid that means nothing on
# the target machine.
dpkg-deb --root-owner-group --build "$ROOT" "$DEB" >/dev/null
echo "    $DEB  ($(du -h "$DEB" | cut -f1))"

echo
echo "==> Verifying the package"
dpkg-deb --info "$DEB" | sed -n 's/^ /    /p' | head -12
echo "    ---"
echo "    files: $(dpkg-deb --contents "$DEB" | wc -l)"
dpkg-deb --contents "$DEB" | grep -E "opt/darkmoon/darkmoon$|darkmoon.desktop|darkmoon.png" |
  awk '{print "    " $6}'
