import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../native/image_utils.dart';
import '../crop_transform.dart';
import '../histogram.dart';
import '../render_job.dart';
import 'mask_gpu.dart';
import 'render_gpu.dart';

/// GPU counterpart to `render_job.dart`'s `renderJobToJpeg` — same crop/
/// render/histogram/JPEG/thumbnail-encode shape and the same [RenderResult]
/// output, but calls [renderRgbGpu]/[renderRgbWithMasksGpu] instead of the
/// CPU pipeline (dispatched on whether [RenderJob.masks] is empty, same as
/// `renderJobToJpeg`'s own CPU dispatch).
///
/// **Must run on the main isolate, not via `compute()`** — see
/// `render_gpu.dart`'s doc comment. Unlike the CPU path, this whole
/// function (render *and* encode) runs inline: splitting the encode step
/// into its own `compute()` isolate call would need the rendered pixels
/// (or its own crop-geometry inputs) to round-trip through isolate-
/// transferable data anyway, and the encode step's own cost is small next
/// to the GPU render itself — not worth the extra complexity for a first
/// cut. Revisit if profiling shows it matters.
Future<RenderResult> renderJobToJpegGpu(RenderJob job) async {
  final geometry = applyCropTransform(
    job.source.rgbBytes,
    job.source.width,
    job.source.height,
    job.cropTransform,
  );
  final rendered = job.masks.isEmpty
      ? await renderRgbGpu(
          geometry.width,
          geometry.height,
          geometry.rgbBytes,
          job.params,
        )
      : await renderRgbWithMasksGpu(
          geometry.width,
          geometry.height,
          geometry.rgbBytes,
          job.params,
          job.masks,
        );
  final histogram = computeHistogram(rendered);
  final image = img.Image.fromBytes(
    width: geometry.width,
    height: geometry.height,
    bytes: rendered.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final jpegBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
  final thumbnail = fitToMaxDimension(image, filmstripThumbnailMaxDimension);
  final thumbnailBytes = Uint8List.fromList(
    img.encodeJpg(thumbnail, quality: 85),
  );
  return RenderResult(
    jpegBytes: jpegBytes,
    histogram: histogram,
    thumbnailBytes: thumbnailBytes,
  );
}
