import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Disk cache of a photo's *decoded native-resolution* source, stored as a
/// high-quality JPEG so re-opening a photo — or the dynamic full-res
/// preview (`AppSettings.dynamicFullPreview`) — can skip the slow RAW
/// demosaic and load pixels straight from here instead.
///
/// One file per photo (`<sha1(path|mtime|size)>.jpg`, ~5–15 MB each),
/// unlike the thumbnail/preview caches' per-month aggregate files: these
/// blobs are far too big to rewrite a whole bundle on every addition.
///
/// **Bounded**, unlike the other on-disk caches: a total-size cap with LRU
/// eviction (least-recently-*read* first, tracked via each file's mtime,
/// which [lookup] bumps on a hit). Main-isolate-only, same as
/// `ThumbnailCacheManager`.
class NativeSourceCache {
  NativeSourceCache(this.cacheDir, {this.maxBytes = _defaultMaxBytes});

  /// 3 GB — a few hundred cached native sources. Big, but this is an
  /// opt-in feature and the win (skipping a multi-second RAW decode) is
  /// worth the disk.
  static const int _defaultMaxBytes = 3 * 1024 * 1024 * 1024;

  final String cacheDir;
  final int maxBytes;

  File _fileFor(String path, DateTime modified, int size) {
    final raw = '$path|${modified.microsecondsSinceEpoch}|$size';
    final key = sha1.convert(utf8.encode(raw)).toString();
    return File(p.join(cacheDir, '$key.jpg'));
  }

  /// The cached native-source JPEG for [path], or null on a miss. A hit
  /// touches the file's mtime so it survives the next [_evict].
  Future<Uint8List?> lookup(String path) async {
    try {
      final stat = await File(path).stat();
      final file = _fileFor(path, stat.modified, stat.size);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      try {
        await file.setLastModified(DateTime.now());
      } catch (_) {
        // Touch is best-effort; a failed touch just makes this entry look
        // older than it is to the LRU, never breaks the read.
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Writes [jpegBytes] for [path], then evicts oldest entries if the cache
  /// is over [maxBytes]. Best-effort — a failure here never breaks
  /// rendering, it just means the next open re-decodes.
  Future<void> store(String path, Uint8List jpegBytes) async {
    try {
      final stat = await File(path).stat();
      final file = _fileFor(path, stat.modified, stat.size);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(jpegBytes);
      await tmp.rename(file.path);
      await _evict();
    } catch (_) {
      // Ignore.
    }
  }

  Future<void> _evict() async {
    try {
      final dir = Directory(cacheDir);
      final entries = <({File file, FileStat stat})>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          final stat = await entity.stat();
          entries.add((file: entity, stat: stat));
          total += stat.size;
        }
      }
      if (total <= maxBytes) {
        return;
      }
      entries.sort((a, b) => a.stat.modified.compareTo(b.stat.modified));
      for (final entry in entries) {
        if (total <= maxBytes) {
          break;
        }
        try {
          await entry.file.delete();
          total -= entry.stat.size;
        } catch (_) {
          // Skip a locked file; the next store's evict will retry.
        }
      }
    } catch (_) {
      // Ignore.
    }
  }

  /// Deletes every cached native source — for a Settings "clear cache"
  /// action. The current total size on disk, for showing in Settings.
  Future<int> totalBytes() async {
    try {
      final dir = Directory(cacheDir);
      if (!await dir.exists()) {
        return 0;
      }
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          total += await entity.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clearAll() async {
    try {
      final dir = Directory(cacheDir);
      if (!await dir.exists()) {
        return;
      }
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.jpg')) {
          try {
            await entity.delete();
          } catch (_) {
            // Best-effort.
          }
        }
      }
    } catch (_) {
      // Ignore.
    }
  }
}

/// Resolves (creating if needed) `Documents/darkmoon/native-source-cache`.
Future<String> resolveNativeSourceCacheDir() async {
  final documents = await getApplicationDocumentsDirectory();
  final dir = Directory(
    p.join(documents.path, 'darkmoon', 'native-source-cache'),
  );
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}
