import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_utils.dart';
import 'libraw.dart';

/// Embedded camera preview JPEGs are often nearly full-resolution (multiple
/// megapixels) — way more than a filmstrip thumbnail needs. Downscaling
/// before re-encoding is what actually matters for speed: encoding a
/// full-size image dominates the cost (~3.5s), not the LibRaw extraction
/// (~20ms) or JPEG decode (~1.1s) it's layered on top of.
const int thumbnailMaxDimension = 200;

/// Extracts + decodes a RAW file's embedded thumbnail, bakes in its EXIF
/// orientation (so portrait shots don't come out sideways — Flutter's own
/// image codecs don't apply EXIF orientation automatically), downscales it,
/// and re-encodes it as JPEG bytes ready for `Image.memory`.
///
/// Pure decode — no disk cache lookup here. Caching lives in
/// catalog/thumbnail_cache.dart's ThumbnailCacheManager, which is
/// main-isolate-only (it batches writes across a whole month file, which
/// isn't safe to do from multiple concurrent compute() isolates at once);
/// callers should check the cache before calling this and store the
/// result after.
///
/// Designed to run via `compute()`: it's a top-level function taking/
/// returning simple, isolate-transferable data, and the LibRaw call it
/// wraps is blocking.
Uint8List? decodeRawThumbnail(String path) {
  final jpegBytes = extractRawThumbnailJpeg(path);
  if (jpegBytes == null) {
    return null;
  }
  final decoded = img.decodeJpg(jpegBytes);
  if (decoded == null) {
    return null;
  }
  final oriented = img.bakeOrientation(decoded);
  final resized = fitToMaxDimension(oriented, thumbnailMaxDimension);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}
