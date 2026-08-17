import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../native/edit_source.dart';
import '../native/image_utils.dart';
import 'crop_transform.dart';
import 'histogram.dart';
import 'mask.dart';
import 'render.dart';
import 'render_params.dart';

/// Matches thumbnail_loader.dart's thumbnailMaxDimension — kept as its own
/// constant here to avoid this file depending on the thumbnail loader just
/// for one number.
const int _filmstripThumbnailMaxDimension = 200;

/// A single `compute()` request: apply [params] (and any [masks], stacked
/// on top) to [source] and encode the result as JPEG. Bundled into one
/// object because `compute()` only takes one argument.
class RenderJob {
  const RenderJob({
    required this.source,
    required this.params,
    this.masks = const [],
    this.cropTransform = const CropTransformParams(),
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
RenderResult renderJobToJpeg(
  RenderJob job, {
  void Function(RenderStage stage)? onStage,
}) {
  final geometry = applyCropTransform(
    job.source.rgbBytes,
    job.source.width,
    job.source.height,
    job.cropTransform,
  );
  final rendered = job.masks.isEmpty
      ? renderRgb(
          geometry.width,
          geometry.height,
          geometry.rgbBytes,
          job.params,
          onStage: onStage,
        )
      : renderRgbWithMasks(
          geometry.width,
          geometry.height,
          geometry.rgbBytes,
          job.params,
          job.masks,
        );
  onStage?.call(RenderStage.encoding);
  final histogram = computeHistogram(rendered);
  final image = img.Image.fromBytes(
    width: geometry.width,
    height: geometry.height,
    bytes: rendered.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final jpegBytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
  final thumbnail = fitToMaxDimension(image, _filmstripThumbnailMaxDimension);
  final thumbnailBytes = Uint8List.fromList(
    img.encodeJpg(thumbnail, quality: 85),
  );
  return RenderResult(
    jpegBytes: jpegBytes,
    histogram: histogram,
    thumbnailBytes: thumbnailBytes,
  );
}

class _RenderJobIsolateArgs {
  const _RenderJobIsolateArgs(this.job, this.sendPort);

  final RenderJob job;
  final SendPort sendPort;
}

void _renderJobIsolateEntry(_RenderJobIsolateArgs args) {
  final result = renderJobToJpeg(
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
