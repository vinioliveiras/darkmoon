import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../native/onnx_runtime.dart';
import 'ai_enhance.dart';

class AiEnhanceRequest {
  const AiEnhanceRequest({
    required this.rgbBytes,
    required this.width,
    required this.height,
  });

  /// Packed, row-major, 3 bytes/pixel (0-255) — the full-resolution
  /// decoded source, *before* any tone/color edits (this becomes the new
  /// edit source, same as the original plan's "runs once right after RAW
  /// decode" design).
  final Uint8List rgbBytes;
  final int width;
  final int height;
}

/// One tile's worth of progress, forwarded from [enhanceImage]'s own
/// `onProgress` — `stage` is `'denoise'` then `'upscale'`, matching
/// `ai_enhance.dart`'s two passes in order.
class AiEnhanceProgress {
  const AiEnhanceProgress(this.stage, this.tileIndex, this.totalTiles);

  final String stage;
  final int tileIndex;
  final int totalTiles;
}

/// Exceptions thrown inside a spawned [Isolate] don't carry back to the
/// caller as the original exception object (same reasoning as
/// `export_job.dart`'s `ExportResult`) — failures are reported as a plain
/// message instead.
class AiEnhanceIsolateResult {
  const AiEnhanceIsolateResult.success(this.result) : error = null;

  const AiEnhanceIsolateResult.failure(String message)
    : result = null,
      error = message;

  final AiEnhanceResult? result;
  final String? error;

  bool get success => error == null;
}

Future<AiEnhanceIsolateResult> _enhanceInternal(
  AiEnhanceRequest request,
  void Function(AiEnhanceProgress)? onProgress,
) async {
  try {
    // OnnxModel.forSpec's cache is a static field, scoped to whichever
    // isolate is running — this isolate creates (and pays the ~1-2s
    // DirectML-probe-then-fallback session-creation cost for) its own
    // fresh sessions, same as how LibRaw's own FFI calls work per-isolate
    // elsewhere in this codebase. Negligible next to the tiled-inference
    // time this whole call takes regardless.
    final denoiseModel = OnnxModel.forSpec(denoiseModelSpec);
    final upscaleModel = OnnxModel.forSpec(upscaleModelSpec);
    final result = enhanceImage(
      request.rgbBytes,
      request.width,
      request.height,
      denoise: denoiseModel.runTile,
      upscale: upscaleModel.runTile,
      onProgress: (stage, i, total) =>
          onProgress?.call(AiEnhanceProgress(stage, i, total)),
    );
    return AiEnhanceIsolateResult.success(result);
  } catch (e) {
    return AiEnhanceIsolateResult.failure(e.toString());
  }
}

class _AiEnhanceIsolateArgs {
  const _AiEnhanceIsolateArgs(this.request, this.sendPort);

  final AiEnhanceRequest request;
  final SendPort sendPort;
}

void _aiEnhanceIsolateEntry(_AiEnhanceIsolateArgs args) async {
  final result = await _enhanceInternal(
    args.request,
    (progress) => args.sendPort.send(progress),
  );
  args.sendPort.send(result);
}

/// Runs the full AI Enhance pipeline (denoise + 2x super-resolution) in a
/// dedicated [Isolate] — mirrors `export_job.dart`'s
/// `exportPhotoWithProgress` exactly: a real per-tile progress signal
/// instead of an indeterminate spinner for what can be a 30s-2min
/// operation on a full-resolution photo (see the real timings measured in
/// `tool/onnx_full_image_smoke_test.dart` — CPU fallback is meaningfully
/// slower than GPU, [OnnxModel.usingGpu] tells the caller which happened).
Future<AiEnhanceIsolateResult> enhanceImageWithProgress(
  AiEnhanceRequest request,
  void Function(AiEnhanceProgress progress) onProgress,
) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _aiEnhanceIsolateEntry,
    _AiEnhanceIsolateArgs(request, receivePort.sendPort),
  );
  try {
    await for (final message in receivePort) {
      if (message is AiEnhanceProgress) {
        onProgress(message);
      } else if (message is AiEnhanceIsolateResult) {
        return message;
      }
    }
    return const AiEnhanceIsolateResult.failure(
      'AI Enhance isolate closed unexpectedly',
    );
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
