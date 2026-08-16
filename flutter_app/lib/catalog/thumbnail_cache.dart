import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// One cache file per photo, named by a hash of path+mtime+size (so an
/// edited/replaced file at the same path misses the cache instead of
/// returning a stale thumbnail) — matches the spirit of the Python app's
/// SQLite cache key, just as loose files instead of a database, since that
/// avoids bundling another native library.
String _cacheKey(String path, DateTime modified, int size) {
  final raw = '$path|${modified.microsecondsSinceEpoch}|$size';
  return sha1.convert(utf8.encode(raw)).toString();
}

Future<File?> _cacheFileFor(String path, String cacheDir) async {
  try {
    final stat = await File(path).stat();
    final key = _cacheKey(path, stat.modified, stat.size);
    return File(p.join(cacheDir, '$key.jpg'));
  } catch (_) {
    return null;
  }
}

/// Returns the cached thumbnail JPEG for [path] in [cacheDir], or null if
/// there's no cache entry for the file's current mtime/size.
///
/// Pure dart:io — safe to call from any isolate.
Future<Uint8List?> loadCachedThumbnail(String path, String cacheDir) async {
  final file = await _cacheFileFor(path, cacheDir);
  if (file == null || !await file.exists()) {
    return null;
  }
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Best-effort cache write — a failure here shouldn't break thumbnail
/// loading, so errors are swallowed.
Future<void> saveThumbnailCache(String path, String cacheDir, Uint8List jpegBytes) async {
  final file = await _cacheFileFor(path, cacheDir);
  if (file == null) {
    return;
  }
  try {
    await file.writeAsBytes(jpegBytes);
  } catch (_) {
    // Best effort.
  }
}
