import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../diagnostics/dev_log.dart';
import 'legacy_filename_migration.dart';

/// Which preset (by id) is currently applied to each photo, keyed by
/// absolute file path — persisted so the Presets panel still shows a
/// preset as "applied" after an app restart, not just within a session.
/// A string per photo, so it gets its own tiny file rather than riding in
/// the `Map<String, double>` catalog.
Future<File> _photoPresetFile() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  await migrateLegacyFilename(
    dir,
    'flutter_photo_presets.json',
    'darkmoon_photo_presets.json',
  );
  return File(p.join(dir.path, 'darkmoon_photo_presets.json'));
}

Future<Map<String, String>> loadPhotoPresets() async {
  try {
    final file = await _photoPresetFile();
    if (!await file.exists()) {
      return {};
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return {for (final entry in raw.entries) entry.key: entry.value as String};
  } catch (e, st) {
    DevLog.logError(
      'loadPhotoPresets failed, treating assignments as empty',
      e,
      st,
    );
    return {};
  }
}

Future<void> savePhotoPresets(Map<String, String> photoPresets) async {
  final file = await _photoPresetFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(jsonEncode(photoPresets));
  await tmp.rename(file.path);
}
