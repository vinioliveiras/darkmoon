import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Bump when the AI Enhance pipeline changes in any way that changes its
/// output for the same input (a newer/different model file, a tiling
/// parameter change, a normalization fix) — folded into every cache key,
/// so old entries are simply never looked up again instead of serving a
/// stale result. Mirrors `raw_decode_format_version.dart`'s exact role,
/// scoped to this cache instead.
const int aiEnhanceCacheVersion = 1;

/// `path_provider`-free by design (see `ai_enhance_cache_dir.dart`'s doc
/// comment) — safe to call from a background isolate, unlike resolving
/// the cache directory itself.
String _entryKey(String path, DateTime modified, int size) {
  final raw =
      '$path|${modified.microsecondsSinceEpoch}|$size|v$aiEnhanceCacheVersion';
  return sha1.convert(utf8.encode(raw)).toString();
}

String _entryFile(String cacheDir, String key) =>
    p.join(cacheDir, '$key.png');

/// Looks up a previously-cached AI Enhance result for the photo at [path]
/// (its current `mtime`/`size` must match what it was cached under — an
/// edited/replaced file at the same path misses instead of returning
/// something stale). Returns null on a miss or any read failure (best-
/// effort cache, same discipline as `thumbnail_cache.dart`).
Future<Uint8List?> lookupAiEnhanceCache(String cacheDir, String path) async {
  try {
    final stat = await File(path).stat();
    final file = File(_entryFile(cacheDir, _entryKey(path, stat.modified, stat.size)));
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Stores [pngBytes] (the full-strength, un-blended neural output — PNG
/// because this becomes the base every later edit/export builds on, so it
/// must be lossless, same reasoning as `denoise_cache.dart`'s plan) as the
/// cached AI Enhance result for [path]. tmp-then-rename write, same crash-
/// safety discipline as `catalog_store.dart`/`thumbnail_cache.dart`.
Future<void> storeAiEnhanceCache(
  String cacheDir,
  String path,
  Uint8List pngBytes,
) async {
  try {
    final stat = await File(path).stat();
    final key = _entryKey(path, stat.modified, stat.size);
    final dest = File(_entryFile(cacheDir, key));
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsBytes(pngBytes, flush: true);
    await tmp.rename(dest.path);
  } catch (_) {
    // Best-effort cache; a failure here shouldn't break the enhance flow —
    // the caller already has the result in memory regardless.
  }
}
