import 'dart:io';

import 'package:path/path.dart' as p;

/// Renames [oldName] to [newName] within [dir], if [oldName] exists and
/// [newName] doesn't yet — a one-time migration so existing installs don't
/// lose their saved data when a persisted file's name changes (2026-09-01:
/// every `flutter_*.json` file under `Documents/darkmoon` renamed to
/// `darkmoon_*.json`, explicit user request — the "flutter_" prefix was
/// always an implementation detail, not something a user should ever see
/// in their own Documents folder). Called from each store's own file
/// helper, so every load *and* save goes through it and naturally lands on
/// the new name from then on.
///
/// Best-effort: a locked file or a cross-device rename failure just means
/// the old file isn't picked up this run (falls back to whatever the
/// caller's own "file doesn't exist" handling already does — an empty/
/// default result, never a crash) rather than blocking startup.
Future<void> migrateLegacyFilename(
  Directory dir,
  String oldName,
  String newName,
) async {
  final newFile = File(p.join(dir.path, newName));
  if (await newFile.exists()) {
    return;
  }
  final oldFile = File(p.join(dir.path, oldName));
  if (!await oldFile.exists()) {
    return;
  }
  try {
    await oldFile.rename(newFile.path);
  } catch (_) {
    // Best-effort — see doc comment above.
  }
}
