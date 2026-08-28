import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The decoded native-resolution source for a photo (a high-quality JPEG)
/// is cached the *same way* as the thumbnail and preview caches — via
/// [ThumbnailCacheManager], the shared per-capture-month binary format,
/// keyed by `sha1(path|mtime|size)` — just in its own namespaced
/// directory: `Documents/darkmoon/previews/native`, next to the
/// resolution-namespaced preview dirs.
///
/// The one thing it adds is a size cap: these blobs are ~5–15 MB each
/// (vs. a few hundred KB for a preview), so [evictNativeSourceCache]
/// trims the oldest whole month files once the total grows past
/// [nativeSourceCacheMaxBytes].
Future<String> resolveNativeSourceCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(
    p.join(documents.path, 'darkmoon', 'previews', 'native'),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

/// 3 GB — a few hundred cached native sources. Generous, but this is an
/// opt-in feature and the win (skipping a multi-second RAW demosaic) is
/// worth the disk.
const int nativeSourceCacheMaxBytes = 3 * 1024 * 1024 * 1024;

/// Deletes whole month cache files (oldest-modified first) from [cacheDir]
/// until the total size of its `*.cache` files is under
/// [nativeSourceCacheMaxBytes]. Whole-file granularity keeps this cheap
/// and matches how the month files are written (rewritten as a unit).
/// Best-effort — any failure just leaves the cache as-is.
Future<void> evictNativeSourceCache(String cacheDir) async {
  try {
    final dir = Directory(cacheDir);
    if (!await dir.exists()) {
      return;
    }
    final files = <({File file, FileStat stat})>[];
    var total = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.cache')) {
        final stat = await entity.stat();
        files.add((file: entity, stat: stat));
        total += stat.size;
      }
    }
    if (total <= nativeSourceCacheMaxBytes) {
      return;
    }
    files.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
    for (final entry in files) {
      if (total <= nativeSourceCacheMaxBytes) {
        break;
      }
      try {
        await entry.file.delete();
        total -= entry.stat.size;
      } catch (_) {
        // Skip a locked file; the next eviction retries.
      }
    }
  } catch (_) {
    // Ignore.
  }
}
