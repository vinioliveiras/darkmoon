import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../native/edit_source.dart';
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

/// Runs [renderRgb] on the job's source and encodes the result as JPEG
/// bytes ready for `Image.memory`.
///
/// Designed to run via `compute()`.
Uint8List renderJobToJpeg(RenderJob job) {
  final rendered = renderRgb(job.source.width, job.source.height, job.source.rgbBytes, job.params);
  final image = img.Image.fromBytes(
    width: job.source.width,
    height: job.source.height,
    bytes: rendered.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}
