#!/usr/bin/env bash
# Downloads the ONNX model weights into native_models/.
#
# The weights are gitignored — ddcolor alone is 934MB, over GitHub's 100MB
# per-file limit for repository contents — so a fresh clone builds an app
# whose AI features all report a missing model. They live as assets on the
# `models-v1` release instead, where the 2GB per-file limit applies.
#
# This is what lets CI produce a *distributable* macOS build: the project
# has no Mac, the Apple runners are the only Mac, and until the weights
# were fetchable there was nothing for them to bundle.
#
# Safe to re-run: a file that is already present and already matches its
# checksum is left alone, so this costs nothing on a warm checkout.
set -euo pipefail

TAG="${DARKMOON_MODELS_TAG:-models-v1}"
REPO="${DARKMOON_MODELS_REPO:-vinioliveiras/darkmoon}"

cd "$(dirname "$0")/.."
mkdir -p native_models
MANIFEST="$PWD/tool/models.sha256"

cd native_models

# A checkout on Windows (Git's autocrlf on the hosted runners, and on any
# machine that has it on) hands this script a manifest with CRLF line
# endings, and the carriage return then rides along on every file name:
# `gh release download --pattern "name.onnx\r"` matches nothing, and
# sha256sum -c cannot open "name.onnx\r". Found by the first release.yml
# run, 2026-09-10. Work from a CR-free copy no matter how it arrived.
CLEAN_MANIFEST="$(mktemp)"
trap 'rm -f "$CLEAN_MANIFEST"' EXIT
tr -d '\r' < "$MANIFEST" > "$CLEAN_MANIFEST"
MANIFEST="$CLEAN_MANIFEST"

# Verify first, download only what fails. sha256sum's own -c is the check
# in both places, so there is one definition of "correct" rather than two.
need=()
while read -r sum name; do
  name="${name#\*}"
  [ -n "$name" ] || continue
  if [ -f "$name" ] && echo "$sum *$name" | sha256sum -c --status 2>/dev/null; then
    printf '  ok       %s\n' "$name"
  else
    printf '  missing  %s\n' "$name"
    need+=("$name")
  fi
done < "$MANIFEST"

if [ ${#need[@]} -eq 0 ]; then
  echo "All models present and verified."
  exit 0
fi

echo
echo "Downloading ${#need[@]} model(s) from $REPO@$TAG ..."
for name in "${need[@]}"; do
  # --clobber: a previous run may have left a truncated file behind, and
  # gh refuses to overwrite without it.
  gh release download "$TAG" --repo "$REPO" --pattern "$name" --clobber
done

echo
echo "Verifying ..."
# Re-check everything, not just what was downloaded: a partial transfer
# should fail the script rather than surface later as a model that loads
# and produces garbage.
sha256sum -c "$MANIFEST"
echo "All models present and verified."
