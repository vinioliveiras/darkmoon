import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../catalog/ai_enhance_cache.dart';
import '../raw_files.dart' show isRawFile;
import '../render/ai_enhance.dart';
import '../render/ai_enhance_job.dart'
    show AiEnhanceCancellationToken, AiEnhanceModelInfo, AiEnhanceProgress;
import '../native/onnx_runtime.dart';
import 'common_image.dart';
import 'edit_source.dart';
import 'image_utils.dart';
import 'libraw.dart';

/// Reconstructs the *full* native-resolution [EditSource] from a PNG
/// previously written by [_decodeAndEnhance] (via `storeAiEnhanceCache`)
/// — needed by export, which wants the whole enhanced buffer at its real
/// size, unlike [decodeEditSourcesWithAiEnhance]'s own return value
/// (already downscaled to preview/live for on-screen editing). Runs via
/// `compute()`. Returns null on a corrupt blob.
EditSource? decodeAiEnhanceCacheEntry(Uint8List pngBytes) {
  final decoded = img.decodePng(pngBytes);
  if (decoded == null) {
    return null;
  }
  return EditSource(
    width: decoded.width,
    height: decoded.height,
    rgbBytes: decoded.getBytes(order: img.ChannelOrder.rgb),
  );
}

/// [compute()] argument bundle for [decodeCachedAiEnhanceSources].
class DecodeCachedAiEnhanceArgs {
  const DecodeCachedAiEnhanceArgs(this.pngBytes, this.previewMaxDimension);

  final Uint8List pngBytes;
  final int previewMaxDimension;
}

/// Derives preview/live [EditSourcePair] from a previously-cached AI
/// Enhance PNG — the fast path taken when reselecting (or reopening) a
/// photo Enhance was already applied to, instead of either re-running the
/// neural pipeline or (the bug this fixes) silently falling back to a
/// plain decode while `_paramValues` still claims Enhance is active. Runs
/// via `compute()`. Returns null on a corrupt blob.
EditSourcePair? decodeCachedAiEnhanceSources(DecodeCachedAiEnhanceArgs args) {
  final full = img.decodePng(args.pngBytes);
  if (full == null) {
    return null;
  }
  final previewImage = fitToMaxDimension(full, args.previewMaxDimension);
  final liveImage = fitToMaxDimension(previewImage, livePreviewMaxDimension);
  return EditSourcePair(
    preview: EditSource(
      width: previewImage.width,
      height: previewImage.height,
      rgbBytes: previewImage.getBytes(order: img.ChannelOrder.rgb),
    ),
    live: EditSource(
      width: liveImage.width,
      height: liveImage.height,
      rgbBytes: liveImage.getBytes(order: img.ChannelOrder.rgb),
    ),
  );
}

/// Sibling to `edit_source.dart`'s `decodeEditSources`, for item 13's
/// neural Enhance pipeline instead of a plain decode: full-resolution
/// decode (cache permitting, skips straight to the cached result), then
/// NAFNet-SIDD denoise + Real-ESRGAN 2x upscale (`ai_enhance.dart`'s
/// `enhanceImage`), then derives `preview`/`live` from the *enhanced*
/// buffer — so every later edit/mask/export builds on top of the
/// denoised-and-upscaled image, the same "becomes the new base" model
/// Lightroom's own Enhance uses, not a per-render pipeline stage the way
/// the classical `applyAiDenoise` is.
///
/// Kept in its own file rather than added to `edit_source.dart` — that
/// file stays a plain, ONNX-free decode module; only this one pulls in
/// the neural pipeline's dependencies.
///
/// Messages sent to [onStage] are a [RawDecodeStage] (only while decoding
/// a cache-missed RAW), an [AiEnhanceModelInfo] (once per model, right
/// after each session loads — reports GPU/CPU before the wait starts), or
/// an [AiEnhanceProgress] (while the model is actually running) — all
/// three skipped entirely on a cache hit — same "send the typed event, let
/// the caller `is`-check it" convention `decodeEditSourcesWithProgress`
/// already uses.
///
/// Designed to run via [decodeEditSourcesWithAiEnhance] (a dedicated
/// isolate, since this can take from several seconds — a cache hit — to
/// a minute or more — cold, CPU-fallback inference on a large photo, see
/// the real timings in `tool/onnx_full_image_smoke_test.dart`).
///
/// [enableDenoise]/[enableUpscale] pick which of the two passes actually
/// run (see `ai_enhance.dart`'s `enhanceImage`) — at least one must be
/// true; callers that want neither should skip this function entirely and
/// decode normally instead (`_revertToNormalEditSource` in
/// `editor_screen.dart` does exactly that).
Future<EditSourcePair?> _decodeAndEnhance(
  String path,
  String cacheDir,
  int previewMaxDimension,
  bool enableDenoise,
  bool enableUpscale,
  void Function(Object stage) onStage,
) async {
  int width;
  int height;
  Uint8List enhancedRgb;

  final cachedPng = await lookupAiEnhanceCache(
    cacheDir,
    path,
    denoise: enableDenoise,
    upscale: enableUpscale,
  );
  final cachedImage = cachedPng == null ? null : img.decodePng(cachedPng);

  if (cachedImage != null) {
    width = cachedImage.width;
    height = cachedImage.height;
    enhancedRgb = cachedImage.getBytes(order: img.ChannelOrder.rgb);
  } else {
    final decoded = isRawFile(path)
        ? decodeRawImage(path, fastPreview: false, onStage: onStage)
        : decodeCommonImage(path);
    if (decoded == null) {
      return null;
    }

    // Only the model(s) this run actually needs pay the ~1-2s DirectML-
    // probe-then-fallback session-creation cost — asking for denoise alone
    // shouldn't also load the upscaler.
    final denoiseModel = enableDenoise ? OnnxModel.forSpec(denoiseModelSpec) : null;
    if (denoiseModel != null) {
      onStage(
        AiEnhanceModelInfo(
          denoiseModelSpec.fileName,
          denoiseModel.usingGpu,
          denoiseModel.directMlError,
        ),
      );
    }
    final upscaleModel = enableUpscale ? OnnxModel.forSpec(upscaleModelSpec) : null;
    if (upscaleModel != null) {
      onStage(
        AiEnhanceModelInfo(
          upscaleModelSpec.fileName,
          upscaleModel.usingGpu,
          upscaleModel.directMlError,
        ),
      );
    }
    final enhanced = enhanceImage(
      decoded.rgbBytes,
      decoded.width,
      decoded.height,
      // enhanceImage never actually calls these when the matching
      // enable* flag is false, so the null-asserts below are safe —
      // there's simply no model loaded to call them on in that case.
      denoise: (tile) => denoiseModel!.runTile(tile),
      upscale: (tile) => upscaleModel!.runTile(tile),
      enableDenoise: enableDenoise,
      enableUpscale: enableUpscale,
      onProgress: (stage, i, total) =>
          onStage(AiEnhanceProgress(stage, i, total)),
    );
    width = enhanced.width;
    height = enhanced.height;
    enhancedRgb = enhanced.rgbBytes;

    final enhancedImage = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: enhancedRgb.buffer,
      numChannels: 3,
      order: img.ChannelOrder.rgb,
    );
    await storeAiEnhanceCache(
      cacheDir,
      path,
      Uint8List.fromList(img.encodePng(enhancedImage)),
      denoise: enableDenoise,
      upscale: enableUpscale,
    );
  }

  final full = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: enhancedRgb.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final previewImage = fitToMaxDimension(full, previewMaxDimension);
  final liveImage = fitToMaxDimension(previewImage, livePreviewMaxDimension);
  return EditSourcePair(
    preview: EditSource(
      width: previewImage.width,
      height: previewImage.height,
      rgbBytes: previewImage.getBytes(order: img.ChannelOrder.rgb),
    ),
    live: EditSource(
      width: liveImage.width,
      height: liveImage.height,
      rgbBytes: liveImage.getBytes(order: img.ChannelOrder.rgb),
    ),
  );
}

class _AiEnhanceDecodeIsolateArgs {
  const _AiEnhanceDecodeIsolateArgs(
    this.path,
    this.cacheDir,
    this.previewMaxDimension,
    this.enableDenoise,
    this.enableUpscale,
    this.sendPort,
  );

  final String path;
  final String cacheDir;
  final int previewMaxDimension;
  final bool enableDenoise;
  final bool enableUpscale;
  final SendPort sendPort;
}

void _aiEnhanceDecodeIsolateEntry(_AiEnhanceDecodeIsolateArgs args) async {
  final result = await _decodeAndEnhance(
    args.path,
    args.cacheDir,
    args.previewMaxDimension,
    args.enableDenoise,
    args.enableUpscale,
    (stage) => args.sendPort.send(stage),
  );
  args.sendPort.send(result);
}

/// See [_decodeAndEnhance]. [cacheDir] is `resolveAiEnhanceCacheDir()`'s
/// result — resolved once on the main isolate by the caller (the same
/// `path_provider`-isn't-isolate-safe reasoning every other cache dir in
/// this codebase follows) and passed in rather than resolved here.
///
/// [cancellationToken], if given and cancelled, makes this return `null`
/// right away instead of waiting for the isolate to finish on its own —
/// the `finally` block below still kills it immediately either way, same
/// `Future.any` race `export_job.dart`'s `exportPhotoWithProgress` already
/// uses for the same reason (a 30s-2min ONNX inference is exactly the kind
/// of operation a user expects Cancel to actually stop).
Future<EditSourcePair?> decodeEditSourcesWithAiEnhance(
  String path,
  String cacheDir,
  void Function(Object stage) onStage, {
  required bool enableDenoise,
  required bool enableUpscale,
  int previewMaxDimension = defaultPreviewMaxDimension,
  AiEnhanceCancellationToken? cancellationToken,
}) async {
  final receivePort = ReceivePort();
  final isolate = await Isolate.spawn(
    _aiEnhanceDecodeIsolateEntry,
    _AiEnhanceDecodeIsolateArgs(
      path,
      cacheDir,
      previewMaxDimension,
      enableDenoise,
      enableUpscale,
      receivePort.sendPort,
    ),
  );
  try {
    Future<EditSourcePair?> receiveResult() async {
      await for (final message in receivePort) {
        if (message is RawDecodeStage ||
            message is AiEnhanceModelInfo ||
            message is AiEnhanceProgress) {
          onStage(message);
        } else {
          return message as EditSourcePair?;
        }
      }
      return null;
    }

    final cancellation = cancellationToken == null
        ? Completer<EditSourcePair?>().future
        : cancellationToken.cancelled.then((_) => null);
    return await Future.any([receiveResult(), cancellation]);
  } finally {
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}
