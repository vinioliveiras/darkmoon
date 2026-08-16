import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../native/edit_source.dart';
import 'histogram.dart';
import 'render.dart';
import 'render_params.dart';

/// A single `compute()` request: apply [params] to [source] and encode the
/// result as JPEG. Bundled into one object because `compute()` only takes
/// one argument.
class RenderJob {
  const RenderJob({required this.source, required this.params});

  final EditSource source;
  final RenderParams params;
}

class RenderResult {
  const RenderResult({required this.jpegBytes, required this.histogram});

  final Uint8List jpegBytes;
  final Histogram histogram;
}

/// Runs [renderRgb] on the job's source, encodes the result as JPEG bytes
/// ready for `Image.memory`, and bins it into a histogram — computed here
/// (rather than by re-decoding the JPEG later) since the raw pixel data is
/// already in hand.
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
  return RenderResult(jpegBytes: jpegBytes, histogram: histogram);
}
