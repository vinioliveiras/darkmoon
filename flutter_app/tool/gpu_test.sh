#!/usr/bin/env bash
# Runs one integration_test file on the Windows desktop and closes the app
# the moment the test summary line appears.
#
#   tool/gpu_test.sh integration_test/gpu_point_ops_test.dart [log-file]
#
# Why not `flutter test integration_test/... -d windows`: on this machine,
# under Flutter 3.47.2, that harness loses the VM service partway through
# ("VmServiceDisappearedException", tests "did not complete"). `flutter run`
# with the test file as the entry point drives the same tests and prints
# the same summary, but leaves the app window open when the tests end —
# this script watches the log for the summary and kills both the app and
# `flutter run` right then, instead of waiting for a timeout.
#
# Prints every `[...]` measurement line and the summary; the full log is
# kept at the path given (or a temp file, printed at the end).
set -uo pipefail

TEST="${1:?usage: tool/gpu_test.sh integration_test/<file>.dart [log-file]}"
LOG="${2:-$(mktemp -t gpu_test_XXXXXX.log)}"
cd "$(dirname "$0")/.."

flutter run -d windows --no-pub -t "$TEST" > "$LOG" 2>&1 &
RUN=$!

# Up to 10 minutes: a cold build is ~1 minute, the slowest test file ~4.
for _ in $(seq 1 600); do
  if grep -qE "All tests passed|Some tests failed|Error launching|Lost connection to device" "$LOG"; then
    break
  fi
  kill -0 "$RUN" 2>/dev/null || break
  sleep 1
done

# The app first: `flutter run` then sees the connection drop and exits on
# its own. Give it a few seconds before killing it too.
taskkill //IM darkmoon.exe //F >/dev/null 2>&1
for _ in $(seq 1 15); do
  kill -0 "$RUN" 2>/dev/null || break
  sleep 1
done
kill "$RUN" 2>/dev/null

grep -E "^\[[a-z_ ]+\]|All tests passed|Some tests failed|\[E\]|Error launching" "$LOG" | cut -c1-160
echo "log: $LOG"
grep -qE "All tests passed" "$LOG"
