#!/usr/bin/env bash
# Copies macos/native/*.dylib (and the ONNX models, when present) into a
# built darkmoon.app, then re-signs it.
#
# Not wired into `flutter build macos` yet. Doing that means a Run Script
# build phase inside Runner.xcodeproj, and this project has no Mac to
# verify such an edit on — a broken .pbxproj would take the macOS build
# down with it. A separate script is the same result with a failure mode
# that is obvious instead of mysterious. Wire it in once someone can open
# Xcode.
#
# Usage: tool/bundle_macos_natives.sh <path-to-darkmoon.app>
set -euo pipefail

APP="${1:?usage: bundle_macos_natives.sh <path-to-darkmoon.app>}"
cd "$(dirname "$0")/.."

FRAMEWORKS="$APP/Contents/Frameworks"
RESOURCES="$APP/Contents/Resources"
mkdir -p "$FRAMEWORKS" "$RESOURCES"

echo "==> Copying dylibs into $FRAMEWORKS"
cp -f macos/native/*.dylib "$FRAMEWORKS/"

# The weights are gitignored (~1.2GB), so CI has none — the app runs
# without them and the AI features report a missing model.
if compgen -G "native_models/*.onnx" >/dev/null; then
  echo "==> Copying ONNX models into $RESOURCES/models"
  mkdir -p "$RESOURCES/models"
  cp -f native_models/*.onnx "$RESOURCES/models/"
else
  echo "==> No .onnx models present — skipping (AI features will be inert)"
fi

# Ad-hoc signing (-s -). Enough for the app to launch locally; real
# distribution needs a Developer ID and notarization, which needs a paid
# Apple account this project does not have.
echo "==> Ad-hoc signing"
for lib in "$FRAMEWORKS"/*.dylib; do
  codesign --force --sign - "$lib"
done
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP" 2>&1 | sed 's/^/    /'

echo "==> Done"
ls -la "$FRAMEWORKS" | sed 's/^/    /'
