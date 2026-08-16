import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Per-photo slider values, keyed by absolute RAW file path — persisted so
/// edits survive switching photos, folders and app restarts. Kept in its
/// own file (`flutter_catalog.json`) rather than the Python app's
/// `catalog.json`, since the two use different key casing and this port
/// isn't trying to stay wire-compatible with it.
///
/// Lives in `Documents/darkmoon`, matching where the Python app already
/// keeps its catalog/settings/thumbnail cache.
Future<Directory> _catalogDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(documents.path, 'darkmoon'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<File> _catalogFile() async {
  final dir = await _catalogDir();
  return File(p.join(dir.path, 'flutter_catalog.json'));
}

/// Loads the saved per-photo slider values. Returns an empty map if the
/// file doesn't exist yet or can't be parsed (e.g. corrupted by a crash
/// mid-write on some earlier, less careful version).
Future<Map<String, Map<String, double>>> loadCatalog() async {
  try {
    final file = await _catalogFile();
    if (!await file.exists()) {
      return {};
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return {
      for (final entry in raw.entries)
        entry.key: {
          for (final param in (entry.value as Map<String, dynamic>).entries)
            param.key: (param.value as num).toDouble(),
        },
    };
  } catch (_) {
    return {};
  }
}

/// Saves the full catalog, writing to a temp file and renaming over the
/// real one so a crash mid-write can't leave a corrupt/truncated file.
Future<void> saveCatalog(Map<String, Map<String, double>> edits) async {
  final file = await _catalogFile();
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(jsonEncode(edits));
  await tmp.rename(file.path);
}
