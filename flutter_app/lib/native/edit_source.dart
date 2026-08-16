import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_utils.dart';
import 'libraw.dart';

/// Matches the Python app's PREVIEW_MAX_DIM: the editing pipeline runs
/// against a buffer downscaled to this size, not the sensor's native
/// resolution — comfortably above any reasonably-sized viewport and much
/// cheaper to re-render on every adjustment.
const int previewMaxDimension = 1600;

/// A smaller version of the same buffer, matching PREVIEW_MAX_DIM's
/// LIVE_PREVIEW_MAX_DIM counterpart: used while a slider is actively being
/// dragged so re-rendering stays fast enough to feel live, swapped back out
/// for the full-resolution [previewMaxDimension] render as soon as the drag
/// ends.
const int livePreviewMaxDimension = 800;

/// One decoded working-resolution RGB buffer (packed, 3 bytes/pixel) that
/// the render pipeline reads from.
class EditSource {
  const EditSource({
    required this.width,
    required this.height,
    required this.rgbBytes,
  });

  final int width;
  final int height;
  final Uint8List rgbBytes;
}

/// The two resolutions [decodeEditSources] produces for one photo.
class EditSourcePair {
  const EditSourcePair({required this.preview, required this.live});

  final EditSource preview;
  final EditSource live;
}

Uint8List _rgbBytes(img.Image image) =>
    image.getBytes(order: img.ChannelOrder.rgb);

/// Fully decodes the RAW file at [path] once and derives the two working
/// resolutions the editor renders against, so later adjustments only need
/// to re-run the (much cheaper) pixel-math pipeline, not the RAW decode.
///
/// Designed to run via `compute()`.
EditSourcePair? decodeEditSources(String path) {
  final decoded = decodeRawImage(path, halfSize: true);
  if (decoded == null) {
    return null;
  }
  final full = img.Image.fromBytes(
    width: decoded.width,
    height: decoded.height,
    bytes: decoded.rgbBytes.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final previewImage = fitToMaxDimension(full, previewMaxDimension);
  final liveImage = fitToMaxDimension(previewImage, livePreviewMaxDimension);
  return EditSourcePair(
    preview: EditSource(
      width: previewImage.width,
      height: previewImage.height,
      rgbBytes: _rgbBytes(previewImage),
    ),
    live: EditSource(
      width: liveImage.width,
      height: liveImage.height,
      rgbBytes: _rgbBytes(liveImage),
    ),
  );
}

/// Decodes the RAW file at [path] at full native resolution — no
/// [previewMaxDimension] downscale, and (unlike [decodeEditSources])
/// `halfSize: false` even on sensors where the fast half-size path would
/// otherwise be usable, so "full quality" means the same thing regardless
/// of camera. Backs the editor's opt-in full-quality view toggle: pixel
/// math over 10s of megapixels instead of ~1.7M is a real cost, so this is
/// only decoded when the user explicitly asks for it.
///
/// Designed to run via `compute()`.
EditSource? decodeFullQualitySource(String path) {
  final decoded = decodeRawImage(path, halfSize: false);
  if (decoded == null) {
    return null;
  }
  return EditSource(
    width: decoded.width,
    height: decoded.height,
    rgbBytes: decoded.rgbBytes,
  );
}
