import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../raw_files.dart' show isRawFile;
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
///
/// For a common (non-RAW) image format, decodes the file directly instead
/// of going through LibRaw's embedded-thumbnail extraction — there's no
/// separate camera-generated preview to pull out, the file itself already
/// is the (much smaller than a RAW's demosaiced buffer) source image.
Uint8List? decodeRawThumbnail(String path) {
  if (!isRawFile(path)) {
    final bytes = File(path).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }
    final resized = fitToMaxDimension(decoded, thumbnailMaxDimension);
    final oriented = img.bakeOrientation(resized);
    return Uint8List.fromList(
      img.encodeJpg(oriented, quality: 85, chroma: img.JpegChroma.yuv420),
    );
  }
  final jpegBytes = extractRawThumbnailJpeg(path);
  if (jpegBytes == null) {
    return null;
  }
  final decoded = img.decodeJpg(jpegBytes);
  if (decoded == null) {
    return null;
  }
  // Downscale before baking orientation, not after: bakeOrientation's
  // rotate/flip is O(pixel count), and at full embedded-preview resolution
  // that's often multiple megapixels for a 200px thumbnail. A 90/180/270
  // rotation or flip doesn't care what resolution it runs at, so doing it
  // on the already-downscaled image is the same visual result for a
  // fraction of the pixels touched.
  final resized = fitToMaxDimension(decoded, thumbnailMaxDimension);
  final oriented = img.bakeOrientation(resized);
  return Uint8List.fromList(
    img.encodeJpg(oriented, quality: 85, chroma: img.JpegChroma.yuv420),
  );
}
