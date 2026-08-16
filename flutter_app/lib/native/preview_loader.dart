import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_utils.dart';
import 'libraw.dart';

/// Matches the Python app's PREVIEW_MAX_DIM: the editing preview is capped
/// to this size regardless of the sensor's real resolution, since that's
/// already well above what any reasonably-sized viewport needs and keeps
/// downstream work (display, eventually adjustments) fast.
const int previewMaxDimension = 1600;

/// Fully decodes a RAW file (half-size demosaic, same as the Python app's
/// editing preview — not the fast embedded-thumbnail path), downscales it
/// to at most [previewMaxDimension] on the longest side, and encodes it as
/// JPEG bytes ready for `Image.memory`.
///
/// This is real decoded pixel data, not the camera's own JPEG preview — the
/// image edits (once wired up) will apply to this, not to
/// `decodeRawThumbnail`'s output.
///
/// Designed to run via `compute()`: it's a top-level function taking/
/// returning simple, isolate-transferable data, and the decode is a
/// blocking native call plus non-trivial CPU work (resize + JPEG encode).
Uint8List? decodeRawPreview(String path) {
  final decoded = decodeRawImage(path, halfSize: true);
  if (decoded == null) {
    return null;
  }
  final image = img.Image.fromBytes(
    width: decoded.width,
    height: decoded.height,
    bytes: decoded.rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final resized = fitToMaxDimension(image, previewMaxDimension);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
}
