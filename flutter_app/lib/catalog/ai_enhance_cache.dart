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
const int aiEnhanceCacheVersion = 7;

/// [mode] folds which of denoise/upscale/raw-denoise actually ran (plus
/// the denoise blend strength — see `ai_enhance.dart`'s `enhanceImage` doc
/// on why there's no finer-grained control than a linear blend) into the
/// key — the same photo can be cached under many different results
/// (denoise only at some strength, upscale only, raw-domain denoise, or
/// any combination), and without this a switch between them would
/// incorrectly hit whichever one was cached first. [denoiseStrengthPercent]
/// is a whole percent (0-100) rather than a float specifically so it
/// doesn't fragment the cache into a near-infinite number of
/// near-duplicate entries. [denoiseModelPath] folds in *which* on-device
/// denoise model produced this result (Settings' custom-model picker —
/// null means the bundled default) so switching models is also treated
/// as a distinct result, not a stale hit from whichever model ran first.
/// [upscaleMaxSharpness] does the same for *which* upscale model ran (see
/// `onnx_runtime.dart`'s `realEsrganUpscaleModelSpec`) — only meaningful
/// when [upscale] is true, but always folded in regardless so toggling it
/// back and forth on the same photo never collides with the other mode's
/// entry.
String _modeTag(
  bool denoise,
  bool upscale,
  bool rawDenoise,
  int denoiseStrengthPercent,
  String? denoiseModelPath,
  bool upscaleMaxSharpness,
) => 'd${denoise ? 1 : 0}s$denoiseStrengthPercent'
    'u${upscale ? 1 : 0}'
    'q${upscaleMaxSharpness ? 1 : 0}'
    'r${rawDenoise ? 1 : 0}'
    'm${denoiseModelPath ?? "default"}';

/// `path_provider`-free by design (see `ai_enhance_cache_dir.dart`'s doc
/// comment) — safe to call from a background isolate, unlike resolving
/// the cache directory itself.
String _entryKey(
  String path,
  DateTime modified,
  int size,
  bool denoise,
  bool upscale,
  bool rawDenoise,
  int denoiseStrengthPercent,
  String? denoiseModelPath,
  bool upscaleMaxSharpness,
) {
  final raw =
      '$path|${modified.microsecondsSinceEpoch}|$size|'
      '${_modeTag(denoise, upscale, rawDenoise, denoiseStrengthPercent, denoiseModelPath, upscaleMaxSharpness)}|v$aiEnhanceCacheVersion';
  return sha1.convert(utf8.encode(raw)).toString();
}

// `.aicache` (not `.png`) purely for naming consistency with every other
// on-disk cache in this app (thumbnail_cache.dart's month files,
// native_source_cache.dart's blobs use `.cache`) — the bytes inside are
// still a plain PNG encoding, just not advertised via the extension. A
// dedicated extension rather than reusing `.cache` verbatim, so nothing
// (Explorer, this app's own folder scan, a future generic ".cache sweep")
// mistakes one of these — tens of MB each — for a thumbnail/preview
// blob or, worse, an actual image file. Deliberately NOT migrated to
// those caches' actual per-month-batched ThumbnailCacheManager format:
// that class is main-isolate-only (it batches writes in memory, unsafe
// from multiple isolates), while this cache's lookup/store must run from
// the background isolate `decodeEditSourcesWithAiEnhance` spawns — a
// real architectural mismatch, not just a naming one.
String _entryFile(String cacheDir, String key) =>
    p.join(cacheDir, '$key.aicache');

/// Looks up a previously-cached AI Enhance result for the photo at [path]
/// (its current `mtime`/`size` must match what it was cached under — an
/// edited/replaced file at the same path misses instead of returning
/// something stale), specifically for this [denoise]/[upscale] combination
/// — see [_modeTag]. Returns null on a miss or any read failure (best-
/// effort cache, same discipline as `thumbnail_cache.dart`).
Future<Uint8List?> lookupAiEnhanceCache(
  String cacheDir,
  String path, {
  required bool denoise,
  required bool upscale,
  bool rawDenoise = false,
  int denoiseStrengthPercent = 100,
  String? denoiseModelPath,
  bool upscaleMaxSharpness = false,
}) async {
  try {
    final stat = await File(path).stat();
    final file = File(
      _entryFile(
        cacheDir,
        _entryKey(
          path,
          stat.modified,
          stat.size,
          denoise,
          upscale,
          rawDenoise,
          denoiseStrengthPercent,
          denoiseModelPath,
          upscaleMaxSharpness,
        ),
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

/// Stores [pngBytes] (the full-strength, un-blended neural output — PNG
/// because this becomes the base every later edit/export builds on, so it
/// must be lossless, same reasoning as `denoise_cache.dart`'s plan) as the
/// cached AI Enhance result for [path] under this [denoise]/[upscale]
/// combination. tmp-then-rename write, same crash-safety discipline as
/// `catalog_store.dart`/`thumbnail_cache.dart`.
Future<void> storeAiEnhanceCache(
  String cacheDir,
  String path,
  Uint8List pngBytes, {
  required bool denoise,
  required bool upscale,
  bool rawDenoise = false,
  int denoiseStrengthPercent = 100,
  String? denoiseModelPath,
  bool upscaleMaxSharpness = false,
}) async {
  try {
    final stat = await File(path).stat();
    final key = _entryKey(
      path,
      stat.modified,
      stat.size,
      denoise,
      upscale,
      rawDenoise,
      denoiseStrengthPercent,
      denoiseModelPath,
      upscaleMaxSharpness,
    );
    final dest = File(_entryFile(cacheDir, key));
    final tmp = File('${dest.path}.tmp');
    await tmp.writeAsBytes(pngBytes, flush: true);
    await tmp.rename(dest.path);
  } catch (_) {
    // Best-effort cache; a failure here shouldn't break the enhance flow —
    // the caller already has the result in memory regardless.
  }
}
