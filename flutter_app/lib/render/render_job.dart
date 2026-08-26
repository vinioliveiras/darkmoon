import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../native/edit_source.dart';
import '../native/image_utils.dart';
import 'crop_transform.dart';
import 'histogram.dart';
import 'lens_correction.dart';
import 'mask.dart';
import 'render.dart';
import 'render_parallel.dart';
import 'render_params.dart';

/// Matches thumbnail_loader.dart's thumbnailMaxDimension — kept as its own
/// constant here to avoid this file depending on the thumbnail loader just
/// for one number. Public so `render_job_gpu.dart`'s `renderJobToJpegGpu`
/// can reuse the exact same value for its own thumbnail encode.
const int filmstripThumbnailMaxDimension = 200;

/// A single `compute()` request: apply [params] (and any [masks], stacked
/// on top) to [source] and encode the result as JPEG. Bundled into one
/// object because `compute()` only takes one argument.
class RenderJob {
  const RenderJob({
    required this.source,
    required this.params,
    this.masks = const [],
    this.cropTransform = const CropTransformParams(),
    this.lensCorrection = const LensCorrectionParams(),
    this.lensProfile,
    this.focalLengthMm = 0,
    this.apertureFNumber = 0,
  });

  final EditSource source;
  final RenderParams params;
  final List<MaskLayer> masks;

  /// Crop/rotate/keystone geometry — deliberately global-only (not part of
  /// [RenderParams], which masks also build from their own flat values
  /// map): it changes the buffer's own width/height once, up front, so
  /// masks' normalized coordinates and every color/tone step downstream
  /// all operate in the same already-cropped frame rather than each mask
  /// needing its own independent crop.
  final CropTransformParams cropTransform;

  /// Lens profile geometric/vignetting correction — deliberately kept
  /// alongside [cropTransform] rather than folded into [RenderParams] for
  /// the same reason: it's a whole-photo correction applied once, before
  /// masks exist to stack on top of, not a per-mask-reapplicable slider.
  /// [lensProfile] is already resolved (matched from EXIF or manually
  /// picked — see `lens_correction.dart`'s `resolveLensProfile`) by the
  /// caller before building this job, since that resolution needs the
  /// bundled JSON asset loaded (`rootBundle`, main-isolate-only) while
  /// this job itself may run inside a background isolate via `compute()`.
  final LensCorrectionParams lensCorrection;
  final LensProfile? lensProfile;

  /// From the photo's own EXIF ([RawMetadata.focalLengthMm]/
  /// [RawMetadata.apertureFNumber]) — the calibration data is keyed by
  /// these, not by any slider the user controls.
  final double focalLengthMm;
  final double apertureFNumber;
}

class RenderResult {
  const RenderResult({
    required this.jpegBytes,
    required this.histogram,
    required this.thumbnailBytes,
  });

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
/// [onStage], if given, is called as each [RenderStage] of the adjustment
/// pipeline starts, plus once more ([RenderStage.encoding]) before the
/// JPEG/histogram/thumbnail encoding work below.
///
/// Designed to run via `compute()` (when [onStage] is null) or via
/// [renderJobToJpegWithProgress] otherwise — same reasoning as
/// `edit_source.dart`'s [decodeEditSourcesWithProgress].
///
/// The plain, no-masks, no-progress-tracking case (an ordinary slider-drag
/// settled render — the overwhelming majority of calls) runs on
/// [renderAdjustmentsParallel] instead of the serial [renderRgb], splitting
/// the work across the machine's CPU cores. Masked renders and the
/// progress-tracked AI Denoise apply path stay on the serial pipeline:
/// composing several mask layers' band-parallel results correctly is a
/// bigger job for another day, and the progress-tracked path already
/// spawns its own dedicated isolate for the *whole* call (see
/// [renderJobToJpegWithProgress]) — a one-shot action the user already
/// expects to wait on with a progress bar, not the every-drag hot path
/// this split was built for.
Future<RenderResult> renderJobToJpeg(
  RenderJob job, {
  void Function(RenderStage stage)? onStage,
}) async {
  final undistorted = applyResolvedLensDistortion(job);
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
  final correctedRgb = applyResolvedLensVignette(
    job,
    geometry.rgbBytes,
    geometry.width,
    geometry.height,
  );
  final Uint8List rendered;
  if (job.masks.isEmpty && onStage == null) {
    rendered = await renderAdjustmentsParallel(
      geometry.width,
      geometry.height,
      correctedRgb,
      job.params,
    );
  } else {
    rendered = job.masks.isEmpty
        ? renderRgb(
            geometry.width,
            geometry.height,
            correctedRgb,
            job.params,
            onStage: onStage,
          )
        : renderRgbWithMasks(
            geometry.width,
            geometry.height,
            correctedRgb,
            job.params,
            job.masks,
          );
  }
  onStage?.call(RenderStage.encoding);
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

/// Lens distortion correction runs BEFORE [applyCropTransform] (Lightroom
/// applies profile geometric correction before the user's own manual
/// Transform/Crop, so crop coordinates are defined against the corrected
/// image, not the raw distorted one) — a no-op (returns [job.source]'s
/// own buffer, no copy) unless a profile was actually resolved for this
/// job. Shared by `renderJobToJpeg` and `render_job_gpu.dart`'s
/// `renderJobToJpegGpu` so both the CPU and GPU render paths apply the
/// exact same correction before their own pipelines run — this is a pure
/// CPU pixel pass either way (no GPU shader was written for it; see
/// project's lens-correction notes), so it works identically regardless
/// of which pipeline consumes its output afterward.
GeometryResult applyResolvedLensDistortion(RenderJob job) {
  final profile = job.lensProfile;
  if (!job.lensCorrection.enabled || profile == null) {
    return GeometryResult(
      width: job.source.width,
      height: job.source.height,
      rgbBytes: job.source.rgbBytes,
    );
  }
  return applyLensDistortionCorrection(
    job.source.rgbBytes,
    job.source.width,
    job.source.height,
    profile,
    job.focalLengthMm,
    job.lensCorrection.distortionAmount / 100.0,
  );
}

/// TCA (chromatic aberration) correction, applied right after
/// [applyResolvedLensDistortion] and before [applyCropTransform] — like
/// distortion (and unlike vignetting), its radius math is defined against
/// the photo's own optical center, which only still matches the buffer's
/// center pre-crop. A no-op (returns the input buffer, no copy) unless a
/// profile with TCA calibration was actually resolved for this job — same
/// pattern as [applyResolvedLensDistortion], shared by both the CPU and GPU
/// render paths.
GeometryResult applyResolvedLensChromaticAberration(
  RenderJob job,
  Uint8List rgbBytes,
  int width,
  int height,
) {
  final profile = job.lensProfile;
  if (!job.lensCorrection.enabled || profile == null) {
    return GeometryResult(width: width, height: height, rgbBytes: rgbBytes);
  }
  return applyLensChromaticAberrationCorrection(
    rgbBytes,
    width,
    height,
    profile,
    job.focalLengthMm,
    job.lensCorrection.chromaticAberrationAmount / 100.0,
  );
}

/// Lens vignetting correction, applied right after [applyCropTransform]
/// (crop doesn't change the vignetting math — it's still measured from
/// the *original* optical center, which [applyLensVignetteCorrection]
/// recomputes as the buffer's own current center; a crop that's roughly
/// centered is close enough, and Lightroom itself has the same
/// limitation for an off-center crop). Runs before the main tone/color
/// pipeline and before mask compositing — see `RenderJob.lensCorrection`'s
/// doc comment for why this lives here rather than in `render.dart`'s
/// per-mask-reapplied point-ops.
///
/// Returns the buffer callers should use from here on — NOT necessarily
/// [rgbBytes] itself. [rgbBytes] may still be the exact same object as
/// [RenderJob.source]'s own cached buffer at this point: both
/// [applyResolvedLensDistortion] and [applyCropTransform] return their
/// input unchanged (no copy) when there's nothing for them to do, which
/// is the common case for a lens with vignetting-only calibration data
/// (no distortion entries) and no manual crop. [applyLensVignetteCorrection]
/// mutates in place, so correcting straight into that shared buffer would
/// permanently corrupt the cached source — every subsequent render of the
/// same photo (every further slider tick) would re-darken/re-brighten an
/// already-corrected buffer instead of starting fresh each time. A
/// defensive copy, made only when correction is actually going to run,
/// avoids that at a cost that's negligible next to the correction's own
/// per-pixel loop right after it.
Uint8List applyResolvedLensVignette(
  RenderJob job,
  Uint8List rgbBytes,
  int width,
  int height,
) {
  final profile = job.lensProfile;
  if (!job.lensCorrection.enabled || profile == null) {
    return rgbBytes;
  }
  final buffer = Uint8List.fromList(rgbBytes);
  applyLensVignetteCorrection(
    buffer,
    width,
    height,
    profile,
    job.focalLengthMm,
    job.apertureFNumber,
    job.lensCorrection.vignetteAmount / 100.0,
  );
  return buffer;
}

class _RenderJobIsolateArgs {
  const _RenderJobIsolateArgs(this.job, this.sendPort);

  final RenderJob job;
  final SendPort sendPort;
}

void _renderJobIsolateEntry(_RenderJobIsolateArgs args) async {
  final result = await renderJobToJpeg(
    args.job,
    onStage: (stage) => args.sendPort.send(stage),
  );
  args.sendPort.send(result);
}

/// Same work as [renderJobToJpeg], but run in a dedicated [Isolate] so
/// [onProgress] can be called as each [RenderStage] starts — same pattern
/// as `export_job.dart`'s `exportPhotoWithProgress`. Reserved for the
/// slowest single-shot render (the AI Denoise apply action) rather than
/// every routine slider-drag render: spawning a fresh isolate per call has
/// its own overhead, which would fight the 25ms live-preview debounce if
/// used there instead of the plain `compute()`-based [renderJobToJpeg].
Future<RenderResult> renderJobToJpegWithProgress(
  RenderJob job,
  void Function(RenderStage stage) onProgress,
) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _renderJobIsolateEntry,
    _RenderJobIsolateArgs(job, receivePort.sendPort),
  );
  try {
    await for (final message in receivePort) {
      if (message is RenderStage) {
        onProgress(message);
      } else {
        return message as RenderResult;
      }
    }
    throw StateError('Render isolate closed unexpectedly');
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
