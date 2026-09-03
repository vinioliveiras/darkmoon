import 'package:flutter/foundation.dart' show compute;

import '../render_job.dart';
import 'mask_gpu.dart';
import 'render_gpu.dart';

/// GPU counterpart to `render_job.dart`'s `renderJobToJpeg` — same crop/
/// render/histogram/JPEG/thumbnail-encode shape and the same [RenderResult]
/// output, but calls [renderRgbaGpu]/[renderRgbaWithMasksGpu] instead of the
/// CPU pipeline (dispatched on whether [RenderJob.masks] is empty, same as
/// `renderJobToJpeg`'s own CPU dispatch).
///
/// **Only the render itself must run on the main isolate** — see
/// `render_gpu.dart`'s doc comment. Everything around it is plain CPU work
/// over plain byte buffers, so both halves go through `compute()`:
///
/// - the lens/crop geometry pass before it ([prepareRenderGeometry]), but
///   only when it would actually touch a pixel — it's a no-op returning
///   the source buffer uncopied otherwise, and offloading *that* would add
///   an isolate round-trip of the whole buffer for nothing;
/// - the histogram + JPEG + thumbnail encode after it
///   ([encodeRenderResult]), unconditionally.
///
/// This split replaces an earlier version that ran the entire function
/// inline on the main isolate, on the assumption that "the encode step's
/// own cost is small next to the GPU render itself". That was backwards:
/// the GPU render is milliseconds, while `package:image`'s pure-Dart JPEG
/// encoder costs hundreds of milliseconds on a full-quality frame — so
/// every settled GPU render froze the canvas and stalled any running
/// animation for the whole encode.
Future<RenderResult> renderJobToJpegGpu(RenderJob job) async {
  // The lens corrections and the crop/rotate/keystone transform are CPU
  // pixel passes either way — no GPU shader was written for them (see
  // `RenderJob.lensCorrection`'s doc comment) — so they're baked into the
  // buffer before it's uploaded as a `ui.Image` below.
  final geometry = renderJobNeedsGeometryPass(job)
      ? await compute(prepareRenderGeometry, job)
      : prepareRenderGeometry(job);

  // Same as the CPU path: every neighbourhood radius scales with the frame
  // this render actually runs on, so the quick preview, the full-quality
  // preview and the export all apply the same fraction of the scene. Set
  // here because crop and lens geometry are what settle the dimensions.
  final params = job.params.withRenderScaleFor(geometry.width, geometry.height);
  final rendered = job.masks.isEmpty
      ? await renderRgbaGpu(
          geometry.width,
          geometry.height,
          geometry.rgbBytes,
          params,
        )
      : await renderRgbaWithMasksGpu(
          geometry.width,
          geometry.height,
          geometry.rgbBytes,
          params,
          job.masks,
        );

  final sidecar = await compute(
    computeRenderSidecar,
    RenderEncodeRequest(
      rgbaBytes: rendered,
      width: geometry.width,
      height: geometry.height,
    ),
  );
  return RenderResult(
    previewRgba: rendered,
    previewWidth: geometry.width,
    previewHeight: geometry.height,
    histogram: sidecar.histogram,
    thumbnailBytes: sidecar.thumbnailBytes,
  );
}
