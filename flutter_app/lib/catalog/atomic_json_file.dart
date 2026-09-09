import 'dart:convert';
import 'dart:io';

import '../diagnostics/dev_log.dart';

/// The read and write halves shared by every JSON store in
/// `Documents/darkmoon` (catalog, curves, masks, photo presets, settings).
///
/// Two problems the stores used to share, both found in the 2026-09-09
/// review:
///
/// 1. **Overlapping writes on one temp path.** Each store wrote
///    `<file>.tmp` and renamed it over the real file — atomic against a
///    crash, but not against itself. The editor fires saves from a debounce
///    timer, from photo switches and from paste-edits without awaiting one
///    another, so two writers could truncate each other's temp file, the
///    first rename could land a half-written document, and the second
///    could throw `FileSystemException` inside an unawaited future.
///    [writeJsonFileAtomically] serialises writes per path and gives every
///    write its own temp name.
/// 2. **Corrupt-file amplification.** A file that failed to parse was read
///    as "empty", and the next debounced save then overwrote the damaged
///    but largely intact original with `{}` — one bad byte erased every
///    edit of every photo, permanently. [readJsonObject] now moves such a
///    file aside as `<name>.corrupt-<timestamp>` before the store ever
///    writes again, so the data stays recoverable.

/// The pending write per path. A new write chains onto the previous one
/// so the temp file, the flush and the rename of one save never interleave
/// with another's.
final Map<String, Future<void>> _writeTails = {};

int _tempCounter = 0;

/// Writes [contents] to [file] through a private temp file, flushed and
/// then renamed over the destination, one write at a time per path.
///
/// A failed write leaves the destination as it was and removes its own
/// temp file; the error propagates to the caller after the queue has moved
/// on, so one failure never blocks later saves.
Future<void> writeJsonFileAtomically(File file, String contents) {
  final previous = _writeTails[file.path] ?? Future<void>.value();
  final next = previous
      // A failed predecessor must not poison the chain.
      .catchError((Object _) {})
      .then((_) => _writeOnce(file, contents));
  // Keep the tail alive only while it is the latest; a completed chain
  // holds nothing, and dropping the entry lets the map stay small.
  _writeTails[file.path] = next.catchError((Object _) {});
  return next;
}

Future<void> _writeOnce(File file, String contents) async {
  final tmp = File('${file.path}.tmp.$pid.${_tempCounter++}');
  try {
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  } catch (_) {
    if (await tmp.exists()) {
      try {
        await tmp.delete();
      } catch (_) {
        // The stray temp file is the lesser problem; report the write.
      }
    }
    rethrow;
  }
}

/// Reads [file] as a JSON object. Returns `null` when the file does not
/// exist, and also when it cannot be parsed — but in that case only after
/// renaming it to `<name>.corrupt-<timestamp>` so it survives the next
/// save. [what] names the store in the log line.
Future<Map<String, dynamic>?> readJsonObject(
  File file, {
  required String what,
}) async {
  if (!await file.exists()) {
    return null;
  }
  final text = await file.readAsString();
  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } catch (e, st) {
    final quarantined = await quarantineCorruptFile(file);
    DevLog.logError(
      '$what could not be parsed; moved aside as '
      '${quarantined?.path ?? "(rename failed, left in place)"} and '
      'treated as empty',
      e,
      st,
    );
    return null;
  }
}

/// Renames [file] to `<name>.corrupt-<yyyyMMdd-HHmmss>` and returns the new
/// file, or `null` when the rename itself fails (the original is then left
/// where it was, untouched).
Future<File?> quarantineCorruptFile(File file) async {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  try {
    return await file.rename('${file.path}.corrupt-$stamp');
  } catch (_) {
    return null;
  }
}
