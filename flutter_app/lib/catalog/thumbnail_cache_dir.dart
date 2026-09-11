import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves (creating if needed) the directory cached thumbnails live in —
/// `Documents/darkmoon/thumbnails`, next to the catalog/settings files.
///
/// Kept in its own file, separate from thumbnail_cache.dart's actual
/// cache read/write functions: those need to stay `path_provider`-free
/// since they're pure dart:io and get called from `compute()` isolates
/// (where `path_provider` isn't guaranteed safe) and from the standalone
/// smoke test (which can't load `package:flutter`/`path_provider` at all,
/// since it runs under plain `dart run`, not the Flutter engine). Call
/// this once from the main isolate and pass the resolved path into the
/// isolate-run cache lookups/writes instead.
///
/// `thumbnails-320` since 2026-09-11 (one 320 px size for the filmstrip
/// and the library, see `thumbnailMaxDimension`); the 200 px generation
/// in `thumbnails` is deleted on first sight, it can only ever miss.
Future<String> resolveThumbnailCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final root = p.join(documents.path, 'darkmoon');
  final stale = Directory(p.join(root, 'thumbnails'));
  if (await stale.exists()) {
    try {
      await stale.delete(recursive: true);
    } catch (_) {
      // Left for next time.
    }
  }
  final dir = Directory(p.join(root, 'thumbnails-320'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
