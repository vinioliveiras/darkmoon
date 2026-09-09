import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../raw_files.dart' show isRawFile;
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
RawImage? decodeCommonImage(String path) =>
    decodeCommonImageBytes(File(path).readAsBytesSync());

/// [decodeCommonImage] for bytes already in hand rather than a path — the
/// form the embedded-JPEG path needs, since that JPEG lives inside a RAW
/// container and never exists as a file of its own.
RawImage? decodeCommonImageBytes(Uint8List bytes) {
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

/// The one place that decides *which pixels* a photo is edited and
/// exported from.
///
/// Normally that is the sensor data: LibRaw demosaics the RAW, and a
/// common format (JPEG, PNG, TIFF, WebP, BMP) is simply decoded. With
/// [embeddedJpeg] set, a RAW is read as the camera's own JPEG rendering of
/// the same shot instead — the image the camera would have written if it
/// had been set to JPEG. See [AppSettings.editEmbeddedJpeg].
///
/// Everything that decodes a photo goes through here, so the choice cannot
/// be made in one place and quietly not in another: the editing preview,
/// the export, and each of the three neural pipelines. A photo that opened
/// as its embedded JPEG must export as one too, or what you see is not
/// what you get.
///
/// Falls back to the RAW when [embeddedJpeg] is asked for but the file
/// carries no usable preview — every RAW from a real camera does, but a
/// synthetic or heavily-stripped one may not, and refusing to open it
/// would be a worse answer than opening it the ordinary way.
///
/// [fastPreview] and [onStage] apply to the RAW decode only; neither means
/// anything for an already-encoded image.
RawImage? decodeSourceImage(
  String path, {
  required bool embeddedJpeg,
  bool fastPreview = true,
  void Function(RawDecodeStage stage)? onStage,
}) {
  if (!isRawFile(path)) {
    return decodeCommonImage(path);
  }
  if (embeddedJpeg) {
    final preview = extractRawThumbnailJpeg(path);
    if (preview != null) {
      final decoded = decodeCommonImageBytes(preview);
      if (decoded != null) {
        return decoded;
      }
    }
  }
  return decodeRawImage(path, fastPreview: fastPreview, onStage: onStage);
}
