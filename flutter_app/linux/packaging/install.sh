#!/usr/bin/env bash
# Adds darkmoon to this user's application menu.
#
# It does NOT copy the application anywhere. The bundle is 1.3GB, almost
# all of it model weights, and duplicating that to gain a menu entry is a
# bad trade — so this registers the folder where it already sits. Move or
# delete the folder and the menu entry stops working; re-run this script
# after moving it.
#
# Everything it touches is under $HOME. No root, no system directories,
# nothing that needs undoing by hand — see uninstall.sh.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$APP_DIR/darkmoon"

if [ ! -x "$BIN" ]; then
  echo "error: $BIN not found or not executable." >&2
  echo "Run this script from inside the extracted darkmoon folder." >&2
  exit 1
fi

DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
mkdir -p "$DESKTOP_DIR" "$ICON_DIR"

if [ -f "$APP_DIR/data/icon.png" ]; then
  cp -f "$APP_DIR/data/icon.png" "$ICON_DIR/darkmoon.png"
fi

# No %f and no MimeType: the application does not take a file argument, so
# advertising it as a handler would put darkmoon in "Open With" menus and
# then do nothing when chosen. Worse than being absent.
cat > "$DESKTOP_DIR/darkmoon.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=darkmoon
GenericName=RAW Photo Editor
Comment=Develop and edit RAW photographs
Exec="$BIN"
Icon=darkmoon
Terminal=false
Categories=Graphics;2DGraphics;RasterGraphics;Photography;
Keywords=photo;raw;editor;develop;
StartupWMClass=darkmoon
DESKTOP
chmod 644 "$DESKTOP_DIR/darkmoon.desktop"

# Best-effort: the menu picks the entry up on next login regardless, and
# these tools are not present on every desktop.
command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 &&
  gtk-update-icon-cache -qtf "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" 2>/dev/null || true

echo "darkmoon is now in your application menu."
echo "  launching:  $BIN"
echo "  entry:      $DESKTOP_DIR/darkmoon.desktop"
echo
echo "It may take a moment to appear, or a log out and back in."
echo "To remove it again, run ./uninstall.sh — that leaves this folder alone."
