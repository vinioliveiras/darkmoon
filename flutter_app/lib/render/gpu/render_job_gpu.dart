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
  final undistorted = applyResolvedLensDistortion(job);
  // Same CPU pixel pass `renderJobToJpeg` runs before crop -- no GPU
  // shader for TCA was written either, see `applyResolvedLensVignette`'s
  // doc comment just below for why baking these into the buffer here is
  // fine either way.
  final dechromatized = applyResolvedLensChromaticAberration(
    job,
    undistorted.rgbBytes,
    undistorted.width,
    undistorted.height,
  );
  final geometry = applyCropTransform(
    dechromatized.rgbBytes,
    dechromatized.width,
    dechromatized.height,
    job.cropTransform,
  );
  // Same CPU pixel pass `renderJobToJpeg` runs -- no GPU shader for lens
  // vignetting was written (see `RenderJob.lensCorrection`'s doc comment),
  // so this bakes the correction into the buffer before it's handed to
  // the GPU pipeline below as a `ui.Image` upload. See
  // `applyResolvedLensVignette`'s own doc comment for why its return
  // value (not necessarily `geometry.rgbBytes` itself) is what must be
  // used from here on.
  final correctedRgb = applyResolvedLensVignette(
    job,
    geometry.rgbBytes,
    geometry.width,
    geometry.height,
  );
  final rendered = job.masks.isEmpty
      ? await renderRgbGpu(
          geometry.width,
          geometry.height,
          correctedRgb,
          job.params,
        )
      : await renderRgbWithMasksGpu(
          geometry.width,
          geometry.height,
          correctedRgb,
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
  final jpegBytes = Uint8List.fromList(
    img.encodeJpg(image, quality: 90, chroma: img.JpegChroma.yuv420),
  );
  final thumbnail = fitToMaxDimension(image, filmstripThumbnailMaxDimension);
  final thumbnailBytes = Uint8List.fromList(
    img.encodeJpg(thumbnail, quality: 85, chroma: img.JpegChroma.yuv420),
  );
  return RenderResult(
    jpegBytes: jpegBytes,
    histogram: histogram,
    thumbnailBytes: thumbnailBytes,
  );
}
