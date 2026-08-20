import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

import '../native/common_image.dart';
import '../native/libraw.dart';
import '../raw_files.dart' show isRawFile;
import '../render/crop_transform.dart';
import '../render/mask.dart';
import '../render/render.dart';
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
  });

  final String sourcePath;
  final String destPath;
  final RenderParams params;
  final ExportFormat format;
  final List<MaskLayer> masks;
  final CropTransformParams cropTransform;

  /// JPEG quality (1-100). Ignored for other formats.
  final int quality;
}

/// Exceptions thrown inside a `compute()` isolate don't carry back to the
/// caller as the original exception object, so failures are reported as a
/// plain message instead.
class ExportResult {
  const ExportResult.success(String path) : destPath = path, error = null;

  const ExportResult.failure(String message) : destPath = null, error = message;

  final String? destPath;
  final String? error;

  bool get success => error == null;
}

/// The stages [exportPhotoWithProgress] reports as an export moves through
/// them — coarse (one signal per stage boundary, not a percentage within
/// a stage), but real: each fires exactly when that stage of work starts,
/// unlike a spinner that just spins for the whole call.
enum ExportStage { decoding, rendering, encoding, writing }

ExportResult _exportPhotoInternal(
  ExportRequest request,
  void Function(ExportStage stage)? onStage,
) {
  try {
    onStage?.call(ExportStage.decoding);
    final decoded = isRawFile(request.sourcePath)
        ? decodeRawImage(request.sourcePath, fastPreview: false)
        : decodeCommonImage(request.sourcePath);
    if (decoded == null) {
      return ExportResult.failure('Could not decode ${request.sourcePath}');
    }
    onStage?.call(ExportStage.rendering);
    final geometry = applyCropTransform(
      decoded.rgbBytes,
      decoded.width,
      decoded.height,
      request.cropTransform,
    );
    final rendered = request.masks.isEmpty
        ? renderRgb(
            geometry.width,
            geometry.height,
            geometry.rgbBytes,
            request.params,
          )
        : renderRgbWithMasks(
            geometry.width,
            geometry.height,
            geometry.rgbBytes,
            request.params,
            request.masks,
          );
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
      ExportFormat.jpeg => img.encodeJpg(image, quality: request.quality),
    };
    onStage?.call(ExportStage.writing);
    File(request.destPath).writeAsBytesSync(bytes);
    return ExportResult.success(request.destPath);
  } catch (e) {
    return ExportResult.failure(e.toString());
  }
}

/// Decodes [ExportRequest.sourcePath] at full resolution (unlike the
/// half-size editing preview), applies the same render pipeline used for
/// the on-screen preview, and writes it to [ExportRequest.destPath].
///
/// Mirrors the Python app's `ExportTask.run`. Designed to run via
/// `compute()`: decode + render + encode + file write are all blocking
/// work. Prefer [exportPhotoWithProgress] where stage feedback matters —
/// this plain version exists for callers (like the export smoke test)
/// that just want the result.
ExportResult exportPhoto(ExportRequest request) =>
    _exportPhotoInternal(request, null);

class _ExportIsolateArgs {
  const _ExportIsolateArgs(this.request, this.sendPort);

  final ExportRequest request;
  final SendPort sendPort;
}

void _exportIsolateEntry(_ExportIsolateArgs args) {
  final result = _exportPhotoInternal(
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
  void Function(ExportStage stage) onProgress,
) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _exportIsolateEntry,
    _ExportIsolateArgs(request, receivePort.sendPort),
  );
  try {
    await for (final message in receivePort) {
      if (message is ExportStage) {
        onProgress(message);
      } else if (message is ExportResult) {
        return message;
      }
    }
    return const ExportResult.failure('Export isolate closed unexpectedly');
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
