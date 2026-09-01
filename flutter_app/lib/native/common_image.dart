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
  // `getBytes` only reorders channels — it does NOT rescale bit depth or
  // drop an alpha channel, it just returns the image's native buffer. A
  // 16-bit TIFF (real bug, 2026-09-01: a Fujifilm camera TIFF decoded as
  // pure noise) or a PNG with an alpha channel would otherwise hand back a
  // buffer wider than the 3-bytes/pixel 8-bit RGB every downstream caller
  // (`RawImage.rgbBytes`) assumes, silently misaligning every pixel.
  // `convert` rescales channel values to 8-bit and drops/adds channels as
  // needed, so this always produces the packed shape `RawImage` expects.
  final normalized = oriented.convert(format: img.Format.uint8, numChannels: 3);
  return RawImage(
    width: normalized.width,
    height: normalized.height,
    rgbBytes: normalized.getBytes(order: img.ChannelOrder.rgb),
  );
}
