#!/usr/bin/env bash
# Produces the macOS native libraries darkmoon loads at runtime, into
# macos/native/. Run on a Mac (or a macOS CI runner) — nothing here is
# cross-compilable from Windows/Linux, which is why these are fetched and
# built rather than committed the way the Windows and Linux ones are.
#
#   ONNX Runtime          official release tarball
#   WebGPU plugin EP      PyPI wheel (no GitHub release asset exists)
#   LibRaw                built from source
#
# LibRaw is the one that needs real work: it links against libjpeg, lcms2
# and zlib, and unlike Linux, macOS ships none of them. Homebrew's copies
# are in /opt/homebrew, which is not a path a distributed .app can depend
# on, so its dependencies are copied in beside it and every install_name
# is rewritten to @rpath.
set -euo pipefail

ORT_VERSION=1.24.4
WEBGPU_EP_VERSION=0.3.0
LIBRAW_VERSION=0.22.0

cd "$(dirname "$0")/.."
OUT="$PWD/macos/native"
WORK="$(mktemp -d)"
mkdir -p "$OUT"
trap 'rm -rf "$WORK"' EXIT

echo "==> ONNX Runtime $ORT_VERSION"
curl -fsSL -o "$WORK/ort.tgz" \
  "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/onnxruntime-osx-arm64-${ORT_VERSION}.tgz"
tar xzf "$WORK/ort.tgz" -C "$WORK"
cp "$WORK/onnxruntime-osx-arm64-${ORT_VERSION}/lib/libonnxruntime.${ORT_VERSION}.dylib" \
  "$OUT/libonnxruntime.dylib"

echo "==> WebGPU plugin EP $WEBGPU_EP_VERSION"
python3 - "$WEBGPU_EP_VERSION" "$OUT" <<'PY'
import io, json, sys, urllib.request, zipfile
version, out = sys.argv[1], sys.argv[2]
d = json.load(urllib.request.urlopen(
    f"https://pypi.org/pypi/onnxruntime-ep-webgpu/{version}/json"))
url = next(f['url'] for f in d['urls'] if 'macosx' in f['filename'])
z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(url).read()))
name = next(n for n in z.namelist() if n.endswith('.dylib'))
open(f"{out}/libonnxruntime_providers_webgpu.dylib", 'wb').write(z.read(name))
print("   from", name)
PY

echo "==> LibRaw $LIBRAW_VERSION"
brew list libraw >/dev/null 2>&1 || brew install libraw
brew list dylibbundler >/dev/null 2>&1 || brew install dylibbundler
LIBRAW_DYLIB="$(brew --prefix libraw)/lib/libraw_r.dylib"
cp "$LIBRAW_DYLIB" "$OUT/libraw_r.dylib"

echo "==> Bundling LibRaw's dependencies"
# -of overwrite, -cd create the destination, -b bundle, -x the binary to fix,
# -d where the copies go, -p the path they will be found at inside the .app.
dylibbundler -of -cd -b \
  -x "$OUT/libraw_r.dylib" \
  -d "$OUT" \
  -p "@rpath" \
  -i /usr/lib -i /System/Library

echo "==> Rewriting install names to @rpath"
for lib in "$OUT"/*.dylib; do
  install_name_tool -id "@rpath/$(basename "$lib")" "$lib" 2>/dev/null || true
  # Also give each one @loader_path as an rpath, so the @rpath/... entries
  # dylibbundler wrote resolve relative to the dylib's own directory. Inside
  # the .app that is Contents/Frameworks either way, but it also makes the
  # set self-contained for anything that dlopen's it from elsewhere — which
  # is exactly what tool/native_smoke_test.dart does in CI, from `dart run`,
  # a binary with no rpath pointing here.
  install_name_tool -add_rpath "@loader_path" "$lib" 2>/dev/null || true
done

echo "==> Result"
ls -la "$OUT"
echo
for lib in "$OUT"/*.dylib; do
  echo "--- $(basename "$lib")"
  otool -L "$lib" | tail -n +2 | sed 's/^/    /'
done
