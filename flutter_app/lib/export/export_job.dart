import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:image/image.dart' as img;

import '../native/common_image.dart';
import '../native/image_utils.dart';
import '../native/libraw.dart';
import '../raw_files.dart' show isRawFile;
import '../render/crop_transform.dart';
import '../render/mask.dart';
import '../render/render.dart';
import '../render/render_parallel.dart';
import '../render/render_params.dart';
import 'export_format.dart';

class ExportRequest {
  const ExportRequest({
    required this.sourcePath,
    required this.destPath,
    required this.params,
    required this.format,
    required this.quality,
    this.masks = const [],
    this.cropTransform = const CropTransformParams(),
    this.scalePercent,
    this.preDecodedRgb,
    this.preDecodedWidth,
    this.preDecodedHeight,
  });

  final String sourcePath;
  final String destPath;
  final RenderParams params;
  final ExportFormat format;
  final List<MaskLayer> masks;
  final CropTransformParams cropTransform;

  /// JPEG quality (1-100). Ignored for other formats.
  final int quality;

  /// The photo's already-decoded native-resolution RGB (packed, 3 bytes/
  /// pixel) — from the editor's full-quality-preview source or the shared
  /// `previews/native` cache. When set, the export skips the RAW demosaic
  /// entirely (the slowest step, especially for X-Trans). Null = decode
  /// from [sourcePath] as before.
  final Uint8List? preDecodedRgb;
  final int? preDecodedWidth;
  final int? preDecodedHeight;

  /// Scales the exported image to this percent (1-100) of the sensor's
  /// native resolution — applied right after decode, before crop/render/
  /// encode, so every later stage works on fewer pixels too. Decode itself
  /// always stays at full quality (LibRaw's best demosaic) regardless of
  /// this value — only the final pixel dimensions shrink. Null (or 100)
  /// exports at full native resolution, same as before this existed.
  /// Backs the export dialog's "Rapid export" resolution slider.
  final int? scalePercent;
}

/// Exceptions thrown inside a `compute()` isolate don't carry back to the
/// caller as the original exception object, so failures are reported as a
/// plain message instead.
class ExportResult {
  const ExportResult.success(String path, {this.timings})
    : destPath = path,
      error = null;

  const ExportResult.failure(String message)
    : destPath = null,
      error = message,
      timings = null;

  final String? destPath;
  final String? error;

  /// Per-stage timing, e.g. `decode 3200ms · render 900ms · encode 700ms` —
  /// surfaced in the success snackbar while export perf is being profiled.
  final String? timings;

  bool get success => error == null;
}

class ExportCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get cancelled => _completer.future;

  void cancel() {
    if (!isCancelled) {
      _completer.complete();
    }
  }
}

/// The stages [exportPhotoWithProgress] reports as an export moves through
/// them — coarse (one signal per stage boundary, not a percentage within
/// a stage), but real: each fires exactly when that stage of work starts,
/// unlike a spinner that just spins for the whole call.
enum ExportStage { decoding, rendering, encoding, writing }

Future<ExportResult> _exportPhotoInternal(
  ExportRequest request,
  void Function(ExportStage stage)? onStage,
) async {
  try {
    final sw = Stopwatch()..start();
    final timings = <String>[];
    void mark(String stage) {
      final line = '$stage ${sw.elapsedMilliseconds}ms';
      debugPrint('export: $line');
      timings.add(line);
      sw.reset();
    }

    onStage?.call(ExportStage.decoding);
    int width;
    int height;
    Uint8List rgbBytes;
    if (request.preDecodedRgb != null &&
        request.preDecodedWidth != null &&
        request.preDecodedHeight != null) {
      width = request.preDecodedWidth!;
      height = request.preDecodedHeight!;
      rgbBytes = request.preDecodedRgb!;
      mark('reuse decoded source');
    } else {
      final decoded = isRawFile(request.sourcePath)
          ? decodeRawImage(request.sourcePath, fastPreview: false)
          : decodeCommonImage(request.sourcePath);
      if (decoded == null) {
        return ExportResult.failure('Could not decode ${request.sourcePath}');
      }
      width = decoded.width;
      height = decoded.height;
      rgbBytes = decoded.rgbBytes;
      mark('decode');
    }
    final scalePercent = request.scalePercent;
    // Above ~90% the resample costs a full-image resize (seconds at 40 MP)
    // for little pixel reduction and barely any render speed-up — skip it
    // and export at native resolution.
    if (scalePercent != null && scalePercent < 90) {
      final scaled = scaleByPercent(
        img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rgbBytes.buffer,
          numChannels: 3,
          order: img.ChannelOrder.rgb,
        ),
        scalePercent,
      );
      width = scaled.width;
      height = scaled.height;
      rgbBytes = scaled.getBytes(order: img.ChannelOrder.rgb);
      mark('scale to $scalePercent%');
    }
    onStage?.call(ExportStage.rendering);
    final geometry = applyCropTransform(
      rgbBytes,
      width,
      height,
      request.cropTransform,
    );
    // Export never picked up the CPU-parallel render pipeline when it was
    // added — that was only wired into the live-preview path
    // (render_job.dart). Masked exports stay on the serial renderRgbWithMasks
    // (composing several mask layers' band-parallel results correctly is
    // out of scope for now, see render_parallel.dart's own doc comment).
    final renderTimings = <String>[];
    // Every neighbourhood-based radius scales with the frame this render is
    // actually running on, so the same slider value covers the same fraction
    // of the scene in the editing preview, the full-quality preview and the
    // export. Set here rather than by the caller: crop and lens geometry are
    // what settle the real dimensions, and they only just did.
    final params = request.params.withRenderScaleFor(
      geometry.width,
      geometry.height,
    );
    final rendered = request.masks.isEmpty
        ? await renderAdjustmentsParallel(
            geometry.width,
            geometry.height,
            geometry.rgbBytes,
            params,
            timings: renderTimings,
          )
        : renderRgbWithMasks(
            geometry.width,
            geometry.height,
            geometry.rgbBytes,
            params,
            request.masks,
          );
    mark('render ${geometry.width}x${geometry.height}');
    for (final t in renderTimings) {
      timings.add('  · $t');
    }
    final image = img.Image.fromBytes(
      width: geometry.width,
      height: geometry.height,
      bytes: rendered.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
    onStage?.call(ExportStage.encoding);
    final bytes = switch (request.format) {
      ExportFormat.png => img.encodePng(image),
      ExportFormat.tiff => img.encodeTiff(image),
      // 4:2:0 chroma subsampling (half color resolution, full luma) —
      // this package's default is 4:4:4 (no subsampling at all), which
      // produces meaningfully larger files for no visible quality gain at
      // photographic content; 4:2:0 is what cameras, browsers, and
      // Meridian's own JPEG export all use by default.
      ExportFormat.jpeg => img.encodeJpg(
        image,
        quality: request.quality,
        chroma: img.JpegChroma.yuv420,
      ),
    };
    mark('encode ${request.format.name}');
    onStage?.call(ExportStage.writing);
    File(request.destPath).writeAsBytesSync(bytes);
    mark('write');
    return ExportResult.success(request.destPath, timings: timings.join(' · '));
  } catch (e) {
    return ExportResult.failure(e.toString());
  }
}

/// Decodes [ExportRequest.sourcePath] at full resolution, applies the same
/// render pipeline used for the on-screen preview, and writes it to
/// [ExportRequest.destPath].
///
/// Mirrors the Python app's `ExportTask.run`. Designed to run via
/// `compute()`: decode + render + encode + file write are all blocking
/// work. Prefer [exportPhotoWithProgress] where stage feedback matters —
/// this plain version exists for callers (like the export smoke test)
/// that just want the result.
Future<ExportResult> exportPhoto(ExportRequest request) =>
    _exportPhotoInternal(request, null);

class _ExportIsolateArgs {
  const _ExportIsolateArgs(this.request, this.sendPort);

  final ExportRequest request;
  final SendPort sendPort;
}

void _exportIsolateEntry(_ExportIsolateArgs args) async {
  final result = await _exportPhotoInternal(
    args.request,
    (stage) => args.sendPort.send(stage),
  );
  args.sendPort.send(result);
}

/// Same work as [exportPhoto], but run in a dedicated [Isolate] (rather
/// than `compute()`, which spawns its own ephemeral isolate and only
/// returns once, at the very end) so [onProgress] can be called as each
/// [ExportStage] starts — a real, if stage-granular rather than
/// percentage-granular, progress signal instead of an indeterminate
/// spinner for the whole export.
Future<ExportResult> exportPhotoWithProgress(
  ExportRequest request,
  void Function(ExportStage stage) onProgress, {
  ExportCancellationToken? cancellationToken,
}) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _exportIsolateEntry,
    _ExportIsolateArgs(request, receivePort.sendPort),
  );
  try {
    Future<ExportResult> receiveResult() async {
      await for (final message in receivePort) {
        if (message is ExportStage) {
          onProgress(message);
        } else if (message is ExportResult) {
          return message;
        }
      }
      return const ExportResult.failure('Export isolate closed unexpectedly');
    }

    final cancellation = cancellationToken == null
        ? Completer<ExportResult>().future
        : cancellationToken.cancelled.then(
            (_) => const ExportResult.failure('Export cancelled'),
          );
    return await Future.any([receiveResult(), cancellation]);
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
