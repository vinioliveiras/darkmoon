import 'dart:io';

import 'package:image/image.dart' as img;

import 'libraw.dart';

/// Decodes a common (non-RAW) image format — JPEG, PNG, TIFF, WebP, BMP —
/// via `package:image` rather than LibRaw, baking in its EXIF orientation
/// the same way [decodeRawThumbnail]/`decodeRawImage` do for RAW files, so
/// a portrait JPEG doesn't come out sideways.
///
/// Returns the same shape as [RawImage] (packed 8-bit RGB, row-major, 3
/// bytes/pixel) so every downstream caller (edit source derivation,
/// thumbnails, export) can treat a decoded RAW and a decoded common image
/// identically from this point on.
///
/// Blocking file/CPU work — run on a background isolate (e.g. via
/// `compute`), same as [decodeRawImage].
RawImage? decodeCommonImage(String path) {
  final bytes = File(path).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }
  final oriented = img.bakeOrientation(decoded);
  return RawImage(
    width: oriented.width,
    height: oriented.height,
    rgbBytes: oriented.getBytes(order: img.ChannelOrder.rgb),
  );
}
