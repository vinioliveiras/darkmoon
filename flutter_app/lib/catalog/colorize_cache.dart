import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Bump when the colorize pipeline changes in any way that changes its
/// output for the same input (a newer/different model file, a Lab-math
/// fix) — folded into every cache key, same role
/// `ai_enhance_cache.dart`'s `aiEnhanceCacheVersion` plays for that cache.
const int colorizeCacheVersion = 1;

/// `path_provider`-free by design (see `colorize_cache_dir.dart`'s doc
/// comment) — safe to call from a background isolate. [intensityPercent]
/// (0-100, whole percent — same "don't fragment the cache from a slider
/// drag" reasoning as `ai_enhance_cache.dart`'s amount params) is the only
/// real cache-key dimension colorize has, unlike AI Enhance's several
/// independent toggles.
String _entryKey(
  String path,
  DateTime modified,
  int size,
  int intensityPercent,
) {
  final raw =
      '$path|${modified.microsecondsSinceEpoch}|$size|'
      'i$intensityPercent|v$colorizeCacheVersion';
  return sha1.convert(utf8.encode(raw)).toString();
}

String _entryFile(String cacheDir, String key) =>
    p.join(cacheDir, '$key.colorizecache');

/// Looks up a previously-cached colorize result for the photo at [path]
/// (its current `mtime`/`size` must match what it was cached under) at
/// this [intensityPercent]. Returns null on a miss or any read failure
/// (best-effort cache, same discipline as `ai_enhance_cache.dart`).
Future<Uint8List?> lookupColorizeCache(
  String cacheDir,
  String path, {
  required int intensityPercent,
}) async {
  try {
    final stat = await File(path).stat();
    final file = File(
      _entryFile(
        cacheDir,
        _entryKey(path, stat.modified, stat.size, intensityPercent),
      ),
    );
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Stores [pngBytes] (lossless — this becomes the base every later edit/
/// export builds on, same reasoning as `ai_enhance_cache.dart`'s own
/// store) as the cached colorize result for [path] at [intensityPercent].
/// tmp-then-rename write, same crash-safety discipline as
/// `catalog_store.dart`/`thumbnail_cache.dart`.
Future<void> storeColorizeCache(
  String cacheDir,
  String path,
  Uint8List pngBytes, {
  required int intensityPercent,
}) async {
  try {
    final stat = await File(path).stat();
    final key = _entryKey(path, stat.modified, stat.size, intensityPercent);
    final dest = File(_entryFile(cacheDir, key));
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsBytes(pngBytes, flush: true);
    await tmp.rename(dest.path);
  } catch (_) {
    // Best-effort cache; a failure here shouldn't break the colorize flow —
    // the caller already has the result in memory regardless.
  }
}
