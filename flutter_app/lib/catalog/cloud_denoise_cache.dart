import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../cloud_denoise/cloud_denoise_provider.dart';

/// Bump when anything that changes a provider's output for the same input
/// changes (a different fixed prompt, a different Topaz `model` setting) —
/// folded into every cache key, same role as `aiEnhanceCacheVersion`.
const int cloudDenoiseCacheVersion = 1;

/// `path_provider`-free by design, same reasoning as
/// `ai_enhance_cache.dart`'s `_entryKey`.
String _entryKey(
  String path,
  DateTime modified,
  int size,
  CloudDenoiseProviderKind provider,
) {
  final raw =
      '$path|${modified.microsecondsSinceEpoch}|$size|'
      '${provider.name}|v$cloudDenoiseCacheVersion';
  return sha1.convert(utf8.encode(raw)).toString();
}

// `.clouddenoise` — its own extension, not `.aicache`: this cache holds
// results the user paid a third party for, and must invalidate/clear
// independently from the free on-device AI Enhance cache (see
// `cloud_denoise_cache_dir.dart`'s doc). Bytes inside are a plain PNG
// encoding, same "not advertised via the extension" reasoning as
// `.aicache`.
String _entryFile(String cacheDir, String key) =>
    p.join(cacheDir, '$key.clouddenoise');

/// Looks up a previously-paid-for cloud denoise result for the photo at
/// [path] under this [provider] — the current file's `mtime`/`size` must
/// match what it was cached under, same staleness discipline as
/// `ai_enhance_cache.dart`. Returns null on a miss or any read failure.
Future<Uint8List?> lookupCloudDenoiseCache(
  String cacheDir,
  String path,
  CloudDenoiseProviderKind provider,
) async {
  try {
    final stat = await File(path).stat();
    final file = File(
      _entryFile(cacheDir, _entryKey(path, stat.modified, stat.size, provider)),
    );
    if (!await file.exists()) {
      return null;
    }
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Stores [pngBytes] as the cached cloud denoise result for [path] under
/// this [provider]. tmp-then-rename write, same crash-safety discipline as
/// `ai_enhance_cache.dart`/`catalog_store.dart`.
Future<void> storeCloudDenoiseCache(
  String cacheDir,
  String path,
  CloudDenoiseProviderKind provider,
  Uint8List pngBytes,
) async {
  try {
    final stat = await File(path).stat();
    final key = _entryKey(path, stat.modified, stat.size, provider);
    final dest = File(_entryFile(cacheDir, key));
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsBytes(pngBytes, flush: true);
    await tmp.rename(dest.path);
  } catch (_) {
    // Best-effort cache — a failure here shouldn't break the flow, but
    // IS worth calling out: unlike the free AI Enhance cache, a failed
    // write here means a re-visit will pay for the same call again. Kept
    // silent here to match this codebase's existing cache discipline
    // rather than special-casing this one cache's failure path.
  }
}
