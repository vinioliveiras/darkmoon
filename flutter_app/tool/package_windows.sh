#!/usr/bin/env bash
# Packages an already-built Windows bundle two ways:
#
#   darkmoon-v<VER>-windows-x64-portable.zip   portable — extract and run
#   darkmoon-v<VER>-windows-x64-setup.exe      installer — Start Menu, uninstall
#
# Run `flutter build windows --release` first; this only packages.
# Needs Inno Setup 6 (winget install JRSoftware.InnoSetup).
set -euo pipefail

cd "$(dirname "$0")/.."
VER="$(sed -n 's/^version: \([0-9.]*\)+.*/\1/p' pubspec.yaml)"
[ -n "$VER" ] || { echo "error: could not read version from pubspec.yaml" >&2; exit 1; }

BUNDLE="build/windows/x64/runner/Release"
[ -f "$BUNDLE/darkmoon.exe" ] || {
  echo "error: no build at $BUNDLE — run 'flutter build windows --release' first." >&2
  exit 1
}

OUT="$(cd .. && pwd)"
echo "==> darkmoon $VER"

# ------------------------------------------------------------------- zip
# Python's zipfile rather than Compress-Archive: the latter is slow on a
# payload this size and has historically mangled paths. Level 6, not 9 —
# the ONNX weights are most of the bytes and barely compress, so the extra
# time buys almost nothing.
echo "==> Portable zip"
ZIP="$OUT/darkmoon-v${VER}-windows-x64-portable.zip"
python - "$BUNDLE" "$ZIP" <<'PY'
import os, sys, time, zipfile
src, out = sys.argv[1], sys.argv[2]
if os.path.exists(out):
    os.remove(out)
t0 = n = 0
t0 = time.time()
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for root, _, files in os.walk(src):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, os.path.join('darkmoon', os.path.relpath(full, src)))
            n += 1
print('    %d files, %.2f GB, %.0fs' % (n, os.path.getsize(out) / 1e9, time.time() - t0))
PY

# ------------------------------------------------------------- installer
echo "==> Installer"
ISCC=""
for candidate in \
  "$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe" \
  "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
  "/c/Program Files/Inno Setup 6/ISCC.exe"; do
  [ -f "$candidate" ] && { ISCC="$candidate"; break; }
done
[ -n "$ISCC" ] || {
  echo "error: ISCC.exe not found. Install with:" >&2
  echo "  winget install --id JRSoftware.InnoSetup" >&2
  exit 1
}

# Inno resolves relative paths against the .iss file, so everything it is
# handed has to be absolute — and a Windows path, not a POSIX one. cygpath
# rather than `pwd -W`: the earlier attempt wrote
#   pwd -W 2>/dev/null || cd "$X" && pwd
# which groups as ((A && B) || C) && D, so the POSIX fallback ran every
# time and ISCC was handed /d/Documentos/... regardless.
ABS_BUNDLE="$(cygpath -w "$(cd "$BUNDLE" && pwd)")"
ABS_OUT="$(cygpath -w "$OUT")"
ABS_ICON="$(cygpath -w "$(cd windows/runner/resources && pwd)/app_icon.ico")"

MSYS_NO_PATHCONV=1 "$ISCC" \
  "/DAppVersion=$VER" \
  "/DSourceDir=$ABS_BUNDLE" \
  "/DOutputDir=$ABS_OUT" \
  "/DIconFile=$ABS_ICON" \
  "/DOutputBaseFilename=darkmoon-v${VER}-windows-x64-setup" \
  windows/packaging/darkmoon.iss | tail -5

SETUP="$OUT/darkmoon-v${VER}-windows-x64-setup.exe"
echo
# Checked explicitly: ISCC exits 0 on at least one usage error, so a
# missing installer is otherwise indistinguishable from a successful
# run and this script would report success having built nothing.
[ -f "$SETUP" ] || {
  echo "error: ISCC reported no failure but $SETUP does not exist." >&2
  exit 1
}

echo "==> Done"
ls -la "$ZIP" "$SETUP" | sed 's/^/    /'
