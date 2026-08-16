import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../native/edit_source.dart';
import '../native/image_utils.dart';
import 'histogram.dart';
import 'render.dart';
import 'render_params.dart';

/// Matches thumbnail_loader.dart's thumbnailMaxDimension — kept as its own
/// constant here to avoid this file depending on the thumbnail loader just
/// for one number.
const int _filmstripThumbnailMaxDimension = 200;

/// A single `compute()` request: apply [params] to [source] and encode the
/// result as JPEG. Bundled into one object because `compute()` only takes
/// one argument.
class RenderJob {
  const RenderJob({required this.source, required this.params});

  final EditSource source;
  final RenderParams params;
}

class RenderResult {
  const RenderResult({required this.jpegBytes, required this.histogram, required this.thumbnailBytes});

  final Uint8List jpegBytes;
  final Histogram histogram;

  /// A small (~200px) JPEG of the same rendered result, for the filmstrip —
  /// so the thumbnail reflects the current edit instead of staying frozen
  /// at the camera-original preview.
  final Uint8List thumbnailBytes;
}

/// Runs [renderRgb] on the job's source, encodes the result as JPEG bytes
/// ready for `Image.memory`, bins it into a histogram, and derives a small
/// filmstrip thumbnail — all computed here (rather than redoing work later)
/// since the raw pixel data is already in hand.
///
/// Designed to run via `compute()`.
RenderResult renderJobToJpeg(RenderJob job) {
  final rendered = renderRgb(job.source.width, job.source.height, job.source.rgbBytes, job.params);
  final histogram = computeHistogram(rendered);
  final image = img.Image.fromBytes(
    width: job.source.width,
    height: job.source.height,
    bytes: rendered.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final jpegBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
  final thumbnail = fitToMaxDimension(image, _filmstripThumbnailMaxDimension);
  final thumbnailBytes = Uint8List.fromList(img.encodeJpg(thumbnail, quality: 85));
  return RenderResult(jpegBytes: jpegBytes, histogram: histogram, thumbnailBytes: thumbnailBytes);
}
