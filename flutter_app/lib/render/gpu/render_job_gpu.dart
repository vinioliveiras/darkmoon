import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;

import '../histogram.dart';
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
  final rendered = await renderJobToImageGpu(job);
  final ByteData? byteData;
  try {
    byteData = await rendered.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
  } finally {
    rendered.image.dispose();
  }
  if (byteData == null) {
    throw StateError('renderJobToJpegGpu: toByteData returned null');
  }
  return RenderResult(
    previewRgba: byteData.buffer.asUint8List(),
    previewWidth: rendered.width,
    previewHeight: rendered.height,
    histogram: rendered.histogram,
    thumbnailBytes: rendered.thumbnailBytes,
  );
}

/// A finished GPU render as the frame the chain produced, plus what the
/// editor derives from it. The caller owns [image].
class GpuRenderResult {
  const GpuRenderResult({
    required this.image,
    required this.width,
    required this.height,
    required this.histogram,
    required this.thumbnailBytes,
  });

  final ui.Image image;
  final int width;
  final int height;
  final Histogram histogram;
  final Uint8List thumbnailBytes;
}

/// Long edge of the reduced readback the histogram and the filmstrip
/// thumbnail are computed from (2026-09-11). A settled render used to
/// read the whole frame back, copy it into an isolate for the sidecar and
/// upload it again for the canvas — three passes over 25 MB at the
/// default 3072 px preview. The canvas paints the GPU's own image now,
/// and this is all that comes back: the thumbnail is 200 px, and a
/// histogram of a 1024 px bilinear reduction of the frame matches the
/// full frame's to within a fraction of a percent per bin (see
/// `integration_test/gpu_render_job_test.dart`).
const int gpuSidecarReadbackMaxDimension = 1024;

/// [renderJobToJpegGpu] without the full-frame readback — the render the
/// editor's canvas paints. Same geometry pass, same dispatch on
/// [RenderJob.masks]; only the sidecar comes back from the GPU, from a
/// [gpuSidecarReadbackMaxDimension] reduction of the frame.
Future<GpuRenderResult> renderJobToImageGpu(RenderJob job) async {
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
  final image = job.masks.isEmpty
      ? await renderImageGpuFromRgb(
          geometry.width,
          geometry.height,
          geometry.rgbBytes,
          params,
        )
      : await renderImageWithMasksGpu(
          geometry.width,
          geometry.height,
          geometry.rgbBytes,
          params,
          job.masks,
          aiMaskMaps: job.aiMaskMaps,
        );

  final RenderSidecar sidecar;
  try {
    sidecar = await computeGpuRenderSidecar(
      image,
      geometry.width,
      geometry.height,
    );
  } catch (_) {
    image.dispose();
    rethrow;
  }
  return GpuRenderResult(
    image: image,
    width: geometry.width,
    height: geometry.height,
    histogram: sidecar.histogram,
    thumbnailBytes: sidecar.thumbnailBytes,
  );
}

/// Histogram + filmstrip thumbnail of a finished GPU frame, from a
/// [gpuSidecarReadbackMaxDimension] reduction of it read back once and
/// handed to [computeRenderSidecar] in an isolate. [image] is not
/// disposed.
Future<RenderSidecar> computeGpuRenderSidecar(
  ui.Image image,
  int width,
  int height,
) async {
  final small = await scaleGpuImage(
    image,
    width,
    height,
    gpuSidecarReadbackMaxDimension,
  );
  final ByteData? byteData;
  try {
    byteData = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    if (!identical(small, image)) {
      small.dispose();
    }
  }
  if (byteData == null) {
    throw StateError('computeGpuRenderSidecar: toByteData returned null');
  }
  return compute(
    computeRenderSidecar,
    RenderEncodeRequest(
      rgbaBytes: byteData.buffer.asUint8List(),
      width: small.width,
      height: small.height,
    ),
  );
}
