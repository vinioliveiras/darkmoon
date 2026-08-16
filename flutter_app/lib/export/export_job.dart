import 'dart:io';

import 'package:image/image.dart' as img;

import '../native/libraw.dart';
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
  });

  final String sourcePath;
  final String destPath;
  final RenderParams params;
  final ExportFormat format;
  final List<MaskLayer> masks;

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

/// Decodes [ExportRequest.sourcePath] at full resolution (unlike the
/// half-size editing preview), applies the same render pipeline used for
/// the on-screen preview, and writes it to [ExportRequest.destPath].
///
/// Mirrors the Python app's `ExportTask.run`. Designed to run via
/// `compute()`: decode + render + encode + file write are all blocking
/// work.
ExportResult exportPhoto(ExportRequest request) {
  try {
    final decoded = decodeRawImage(request.sourcePath, halfSize: false);
    if (decoded == null) {
      return ExportResult.failure('Could not decode ${request.sourcePath}');
    }
    final rendered = request.masks.isEmpty
        ? renderRgb(
            decoded.width,
            decoded.height,
            decoded.rgbBytes,
            request.params,
          )
        : renderRgbWithMasks(
            decoded.width,
            decoded.height,
            decoded.rgbBytes,
            request.params,
            request.masks,
          );
    final image = img.Image.fromBytes(
      width: decoded.width,
      height: decoded.height,
      bytes: rendered.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
    final bytes = switch (request.format) {
      ExportFormat.png => img.encodePng(image),
      ExportFormat.tiff => img.encodeTiff(image),
      ExportFormat.jpeg => img.encodeJpg(image, quality: request.quality),
    };
    File(request.destPath).writeAsBytesSync(bytes);
    return ExportResult.success(request.destPath);
  } catch (e) {
    return ExportResult.failure(e.toString());
  }
}
