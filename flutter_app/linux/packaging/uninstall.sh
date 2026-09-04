#!/usr/bin/env bash
# Removes the menu entry created by install.sh.
#
# Deliberately does not delete the application folder. This script lives
# inside it, the folder is where the user chose to put it, and deleting
# the thing you are standing in is a bad habit for an uninstaller. Delete
# the folder yourself when you want the disk space back.
set -euo pipefail

DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"

rm -f "$DESKTOP_DIR/darkmoon.desktop" "$ICON_DIR/darkmoon.png"

command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

echo "Menu entry removed."
echo "The application folder itself was left untouched:"
echo "  $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
