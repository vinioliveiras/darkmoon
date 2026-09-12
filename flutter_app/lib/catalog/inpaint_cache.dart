import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'removal.dart';

/// Bump when the removal pipeline changes in a way that changes its
/// output for the same input (another model file, a change to the
/// window geometry in `inpaint.dart`) — folded into every cache key,
/// the role `colorizeCacheVersion` plays for that cache.
const int inpaintCacheVersion = 1;

/// What a photo's removals amount to, as one string: every visible
/// removal's coverage, in order. Hidden ones are left out, so hiding one
/// and showing it again lands on the same entry.
String inpaintRemovalsKey(List<Removal> removals) {
  final encoded = [
    for (final removal in removals)
      if (removal.visible) removal.signature,
  ].join('|');
  return sha1.convert(utf8.encode(encoded)).toString();
}

String _entryKey(String path, DateTime modified, int size, String removals) {
  final raw =
      '$path|${modified.microsecondsSinceEpoch}|$size|'
      'r$removals|v$inpaintCacheVersion';
  return sha1.convert(utf8.encode(raw)).toString();
}

String _entryFile(String cacheDir, String key) =>
    p.join(cacheDir, '$key.inpaintcache');

/// The full-resolution result of applying [removalsKey]'s removals to the
/// photo at [path] (its current mtime and size must match what it was
/// cached under), as PNG bytes; null on a miss or any read failure.
/// `path_provider`-free, so safe from a background isolate.
Future<Uint8List?> lookupInpaintCache(
  String cacheDir,
  String path, {
  required String removalsKey,
}) async {
  try {
    final stat = await File(path).stat();
    final file = File(
      _entryFile(
        cacheDir,
        _entryKey(path, stat.modified, stat.size, removalsKey),
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

Future<void> storeInpaintCache(
  String cacheDir,
  String path,
  Uint8List pngBytes, {
  required String removalsKey,
}) async {
  try {
    final stat = await File(path).stat();
    final key = _entryKey(path, stat.modified, stat.size, removalsKey);
    final dest = File(_entryFile(cacheDir, key));
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsBytes(pngBytes, flush: true);
    await tmp.rename(dest.path);
  } catch (_) {
    // Best-effort cache; the caller already holds the result in memory.
  }
}
