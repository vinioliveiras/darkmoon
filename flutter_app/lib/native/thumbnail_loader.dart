import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../catalog/thumbnail_cache.dart';
import 'image_utils.dart';
import 'libraw.dart';

/// Embedded camera preview JPEGs are often nearly full-resolution (multiple
/// megapixels) — way more than a filmstrip thumbnail needs. Downscaling
/// before re-encoding is what actually matters for speed: encoding a
/// full-size image dominates the cost (~3.5s), not the LibRaw extraction
/// (~20ms) or JPEG decode (~1.1s) it's layered on top of.
const int thumbnailMaxDimension = 200;

class ThumbnailRequest {
  const ThumbnailRequest({required this.path, this.cacheDir});

  final String path;

  /// Resolved once, up front, in the main isolate (via
  /// [resolveThumbnailCacheDir]) and passed in here since `path_provider`
  /// isn't guaranteed safe to call from a `compute()` isolate. Null skips
  /// caching entirely (e.g. the standalone smoke test).
  final String? cacheDir;
}

/// Extracts + decodes a RAW file's embedded thumbnail, bakes in its EXIF
/// orientation (so portrait shots don't come out sideways — Flutter's own
/// image codecs don't apply EXIF orientation automatically), downscales it,
/// and re-encodes it as JPEG bytes ready for `Image.memory` — or returns a
/// cached copy from a previous run if [ThumbnailRequest.cacheDir] has one
/// for the file's current mtime/size.
///
/// Designed to run via `compute()`: it's a top-level function taking/
/// returning simple, isolate-transferable data, and both the LibRaw call
/// and the cache file I/O are blocking.
Future<Uint8List?> decodeRawThumbnail(ThumbnailRequest request) async {
  final cacheDir = request.cacheDir;
  if (cacheDir != null) {
    final cached = await loadCachedThumbnail(request.path, cacheDir);
    if (cached != null) {
      return cached;
    }
  }

  final jpegBytes = extractRawThumbnailJpeg(request.path);
  if (jpegBytes == null) {
    return null;
  }
  final decoded = img.decodeJpg(jpegBytes);
  if (decoded == null) {
    return null;
  }
  final oriented = img.bakeOrientation(decoded);
  final resized = fitToMaxDimension(oriented, thumbnailMaxDimension);
  final result = Uint8List.fromList(img.encodeJpg(resized, quality: 85));

  if (cacheDir != null) {
    await saveThumbnailCache(request.path, cacheDir, result);
  }
  return result;
}
