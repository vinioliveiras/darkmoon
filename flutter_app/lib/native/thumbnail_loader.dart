import 'dart:typed_data';

import 'package:image/image.dart' as img;

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
  final resized = _fitToMaxDimension(oriented, thumbnailMaxDimension);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
}

img.Image _fitToMaxDimension(img.Image image, int maxDimension) {
  final longestSide = image.width > image.height ? image.width : image.height;
  if (longestSide <= maxDimension) {
    return image;
  }
  return image.width >= image.height
      ? img.copyResize(image, width: maxDimension)
      : img.copyResize(image, height: maxDimension);
}
