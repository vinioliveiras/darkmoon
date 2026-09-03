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

/// Reports which execution provider `OnnxModel.forSpec` actually ended up
/// using for one of the two models (see `OnnxModel._providerChain` for the
/// order tried per platform) — sent once per model, right after its
/// session is created and before any tile inference starts, so the caller
/// can warn "this will be slower" *before* the wait, not after.
/// Purely informational: never changes what runs, only what the UI shows
/// and what dev-mode logging records.
class AiEnhanceModelInfo {
  const AiEnhanceModelInfo(
    this.modelName,
    this.usingGpu,
    this.providerLabel,
    this.gpuError,
  );

  final String modelName;
  final bool usingGpu;

  /// Which provider it landed on — "DirectML", "WebGPU" or "CPU". Named
  /// rather than inferred from [usingGpu], since there is more than one
  /// GPU provider now and which one ran is the interesting part.
  final String providerLabel;

  /// The DirectML failure reason, if [usingGpu] is false because that
  /// attempt failed — null if it never ran or succeeded. See
  /// `OnnxModel.gpuError`.
  final String? gpuError;
}

/// Sent when Settings' custom denoise model ([AppSettings
/// .customDenoiseModelPath]) failed to load or run — the pipeline falls
/// back to the bundled default denoise model transparently rather than
/// failing the whole Enhance pass outright, but the caller still needs to
/// tell the user their custom model wasn't actually used this time.
class CustomDenoiseModelFallback {
  const CustomDenoiseModelFallback(this.reason);

  /// The `Object.toString()` of whatever exception the custom model threw
  /// (usually an `OrtException` — a shape mismatch, missing tensor names,
  /// or a corrupt/incompatible file) — technical, shown as-is rather than
  /// translated (same reasoning as `CloudDenoiseException.message`).
  final String reason;
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

/// Lets a caller stop waiting on the AI Enhance isolate (see
/// `edit_source_ai_enhance.dart`'s `decodeEditSourcesWithAiEnhance`)
/// without the isolate itself needing to cooperate — same shape as
/// `export_job.dart`'s `ExportCancellationToken` (duplicated rather than
/// shared: both are a handful of lines, and export/AI-enhance are already
/// separate, independently-evolving isolate wrappers in this codebase).
class AiEnhanceCancellationToken {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get cancelled => _completer.future;

  void cancel() {
    if (!isCancelled) {
      _completer.complete();
    }
  }
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
    //
    // The cache being isolate-scoped is *not* the same as the memory being
    // isolate-scoped: _aiEnhanceIsolateEntry releases these explicitly
    // before the isolate exits, or they leak for the life of the process.
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
  final AiEnhanceIsolateResult result;
  try {
    result = await _enhanceInternal(
      args.request,
      (progress) => args.sendPort.send(progress),
    );
  } finally {
    // See _enhanceInternal's own note on the per-isolate session cache:
    // the cache dies with this isolate, the native sessions behind it do
    // not. See [OnnxModel.releaseAll].
    OnnxModel.releaseAll();
  }
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
