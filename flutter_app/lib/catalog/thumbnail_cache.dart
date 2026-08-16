import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Thumbnails are cached one file per capture month (by source-file mtime,
/// same proxy the Python app uses for "capture month") instead of one file
/// per photo, so a folder with thousands of RAWs doesn't turn into
/// thousands of loose cache files — matching the spirit of the Python
/// app's per-month SQLite database, just as a small custom binary format
/// instead of SQLite, since that avoids bundling another native library
/// for this port.
///
/// Binary layout per month file:
/// `[u32 count] [count x (40-byte hex sha1 key, u32 length)] [concatenated
/// JPEG blobs in the same order]`.
///
/// Entry key is a sha1 of path+mtime+size, so an edited/replaced file at
/// the same path misses the cache instead of returning something stale.
///
/// This class is main-isolate-only (not safe to share across isolates):
/// it keeps parsed month files in memory and batches writes, which only
/// works because Dart's single-threaded event loop makes its own
/// lookup/store calls safe without extra locking. Cross-isolate access to
/// the *files* themselves is avoided by design — only this one instance
/// ever touches them.
class ThumbnailCacheManager {
  ThumbnailCacheManager(this.cacheDir);

  final String cacheDir;
  final Map<String, Map<String, Uint8List>> _months = {};
  final Map<String, Future<Map<String, Uint8List>>> _loading = {};
  final Set<String> _dirtyMonths = {};

  Future<Map<String, Uint8List>> _monthEntries(String monthKey) {
    final cached = _months[monthKey];
    if (cached != null) {
      return Future.value(cached);
    }
    return _loading.putIfAbsent(monthKey, () async {
      final entries = await _readMonthFile(_monthFile(monthKey));
      _months[monthKey] = entries;
      return entries;
    });
  }

  /// Returns the cached thumbnail JPEG for [path], or null if there's no
  /// entry for its current mtime/size.
  Future<Uint8List?> lookup(String path) async {
    try {
      final stat = await File(path).stat();
      final entries = await _monthEntries(_monthKey(stat.modified));
      return entries[_entryKey(path, stat.modified, stat.size)];
    } catch (_) {
      return null;
    }
  }

  /// Records a newly-decoded thumbnail in memory. Call [flush] afterward
  /// (once, after a batch of these) to actually persist it — writing the
  /// whole month file back on every single addition would be wasteful for
  /// a folder with hundreds of new thumbnails.
  Future<void> store(String path, Uint8List jpegBytes) async {
    try {
      final stat = await File(path).stat();
      final monthKey = _monthKey(stat.modified);
      final entries = await _monthEntries(monthKey);
      entries[_entryKey(path, stat.modified, stat.size)] = jpegBytes;
      _dirtyMonths.add(monthKey);
    } catch (_) {
      // Best-effort cache; a failure here shouldn't break thumbnail loading.
    }
  }

  /// Writes every month touched by [store] since the last flush back to
  /// disk. Safe to call often — months with nothing new are skipped.
  Future<void> flush() async {
    final monthKeys = _dirtyMonths.toList();
    _dirtyMonths.clear();
    for (final monthKey in monthKeys) {
      final entries = _months[monthKey];
      if (entries == null) {
        continue;
      }
      await _writeMonthFile(_monthFile(monthKey), entries);
    }
  }

  File _monthFile(String monthKey) => File(p.join(cacheDir, '$monthKey.cache'));
}

String _monthKey(DateTime modified) {
  final year = modified.year.toString().padLeft(4, '0');
  final month = modified.month.toString().padLeft(2, '0');
  return '$year-$month';
}

String _entryKey(String path, DateTime modified, int size) {
  final raw = '$path|${modified.microsecondsSinceEpoch}|$size';
  return sha1.convert(utf8.encode(raw)).toString();
}

const int _headerCountBytes = 4;
const int _keyBytes = 40; // sha1 hex digest length
const int _lengthBytes = 4;

Future<Map<String, Uint8List>> _readMonthFile(File file) async {
  if (!await file.exists()) {
    return {};
  }
  try {
    final bytes = await file.readAsBytes();
    if (bytes.length < _headerCountBytes) {
      return {};
    }
    final view = ByteData.sublistView(bytes);
    final count = view.getUint32(0, Endian.little);
    var offset = _headerCountBytes;
    final keys = <String>[];
    final lengths = <int>[];
    for (var i = 0; i < count; i++) {
      if (offset + _keyBytes + _lengthBytes > bytes.length) {
        return {}; // Truncated/corrupt header — treat as empty rather than crash.
      }
      keys.add(ascii.decode(bytes.sublist(offset, offset + _keyBytes)));
      offset += _keyBytes;
      lengths.add(view.getUint32(offset, Endian.little));
      offset += _lengthBytes;
    }
    final result = <String, Uint8List>{};
    for (var i = 0; i < count; i++) {
      final len = lengths[i];
      if (offset + len > bytes.length) {
        return result; // Truncated data section — return whatever parsed cleanly.
      }
      result[keys[i]] = bytes.sublist(offset, offset + len);
      offset += len;
    }
    return result;
  } catch (_) {
    return {};
  }
}

Future<void> _writeMonthFile(File file, Map<String, Uint8List> entries) async {
  final builder = BytesBuilder();
  final countHeader = ByteData(_headerCountBytes)..setUint32(0, entries.length, Endian.little);
  builder.add(countHeader.buffer.asUint8List());
  for (final entry in entries.entries) {
    builder.add(ascii.encode(entry.key));
    final lengthHeader = ByteData(_lengthBytes)..setUint32(0, entry.value.length, Endian.little);
    builder.add(lengthHeader.buffer.asUint8List());
  }
  for (final value in entries.values) {
    builder.add(value);
  }
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsBytes(builder.toBytes());
  await tmp.rename(file.path);
}
