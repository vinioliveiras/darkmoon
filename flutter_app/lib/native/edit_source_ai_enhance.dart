import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../catalog/ai_enhance_cache.dart';
import '../raw_files.dart' show isRawFile;
import '../render/ai_enhance.dart';
import '../render/ai_enhance_job.dart'
    show
        AiEnhanceCancellationToken,
        AiEnhanceModelInfo,
        AiEnhanceProgress,
        CustomDenoiseModelFallback;
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
/// NAFNet-SIDD denoise + DIS 2x upscale (`ai_enhance.dart`'s
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
/// `editor_screen.dart` does exactly that). [denoiseStrengthPercent] (0-100,
/// meaningful only when [enableDenoise] is true) is a whole-percent blend
/// ratio rather than a raw 0.0-1.0 double specifically so the cache key
/// (see `ai_enhance_cache.dart`) doesn't fragment into a near-infinite
/// number of near-duplicate entries from a slider being dragged through
/// every float in between.
Future<EditSourcePair?> _decodeAndEnhance(
  String path,
  String cacheDir,
  int previewMaxDimension,
  bool enableDenoise,
  bool enableUpscale,
  bool enableRawDenoise,
  int denoiseStrengthPercent,
  String? customDenoiseModelPath,
  int upscaleSharpnessAmount,
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
    rawDenoise: enableRawDenoise,
    denoiseStrengthPercent: denoiseStrengthPercent,
    denoiseModelPath: customDenoiseModelPath,
    upscaleSharpnessAmount: upscaleSharpnessAmount,
  );
  final cachedImage = cachedPng == null ? null : img.decodePng(cachedPng);

  if (cachedImage != null) {
    width = cachedImage.width;
    height = cachedImage.height;
    enhancedRgb = cachedImage.getBytes(order: img.ChannelOrder.rgb);
  } else {
    // Raw-domain denoise (PMRID) runs, when requested, as part of the RAW
    // decode itself — before demosaic, unlike the sRGB pass below. Only
    // possible for a standard Bayer RAW; a null result here (unsupported
    // CFA, or any other decode failure) falls back to the plain decode
    // path exactly like a normal RAW would, so a request for RAW denoise
    // on a file that can't do it degrades to "no raw denoise", not "no
    // photo at all".
    RawImage? rawDenoised;
    if (enableRawDenoise && isRawFile(path)) {
      final rawDenoiseModel = OnnxModel.forSpec(pmridDenoiseModelSpec);
      onStage(
        AiEnhanceModelInfo(
          pmridDenoiseModelSpec.fileName,
          rawDenoiseModel.usingGpu,
          rawDenoiseModel.directMlError,
        ),
      );
      rawDenoised = decodeRawImageWithPmridDenoise(
        path,
        fastPreview: false,
        onStage: onStage,
        denoiseTile: rawDenoiseModel.runPackedTile,
        onDenoiseProgress: (i, total) =>
            onStage(AiEnhanceProgress('raw-denoise', i, total)),
      );
    }
    final usedRawDenoise = rawDenoised != null;

    final decoded =
        rawDenoised ??
        (isRawFile(path)
            ? decodeRawImage(path, fastPreview: false, onStage: onStage)
            : decodeCommonImage(path));
    if (decoded == null) {
      return null;
    }

    // If raw-domain denoise already ran, the sRGB pass would just
    // re-smooth pixels PMRID already cleaned — skip it regardless of what
    // enableDenoise says (the cache key still reflects the caller's
    // actual request, not this internal downgrade).
    final effectiveEnableDenoise = enableDenoise && !usedRawDenoise;

    // Only the model(s) this run actually needs pay the ~1-2s DirectML-
    // probe-then-fallback session-creation cost — asking for denoise alone
    // shouldn't also load the upscaler.
    OnnxModel? denoiseModel;
    if (effectiveEnableDenoise) {
      var usedSpec = customDenoiseModelPath != null
          ? OnnxModelSpec.customDenoiseModel(customDenoiseModelPath)
          : denoiseModelSpec;
      try {
        denoiseModel = OnnxModel.forSpec(usedSpec);
      } catch (e) {
        // A custom model that fails to load (wrong channel count, missing
        // "input"/"output" tensor names, a corrupt file) falls back to the
        // bundled default transparently — see CustomDenoiseModelFallback's
        // doc — rather than failing the whole Enhance pass. The *bundled*
        // model failing to load is a much more fundamental problem (a
        // packaging bug), so that still propagates normally.
        if (customDenoiseModelPath == null) rethrow;
        onStage(CustomDenoiseModelFallback(e.toString()));
        usedSpec = denoiseModelSpec;
        denoiseModel = OnnxModel.forSpec(usedSpec);
      }
      onStage(
        AiEnhanceModelInfo(
          usedSpec.fileName,
          denoiseModel.usingGpu,
          denoiseModel.directMlError,
        ),
      );
    }
    final upscaleModel = enableUpscale
        ? OnnxModel.forSpec(upscaleModelSpec)
        : null;
    if (upscaleModel != null) {
      onStage(
        AiEnhanceModelInfo(
          upscaleModelSpec.fileName,
          upscaleModel.usingGpu,
          upscaleModel.directMlError,
        ),
      );
    }
    // Real-ESRGAN only loads (paying its own ~1-2s session-creation cost,
    // on top of its much larger per-tile inference time) when the
    // sharpness blend actually needs it — see enhanceImage's
    // sharpnessAmount doc for why 0 must stay free.
    final wantSharpen = enableUpscale && upscaleSharpnessAmount > 0;
    final sharpenModel = wantSharpen
        ? OnnxModel.forSpec(realEsrganUpscaleModelSpec)
        : null;
    if (sharpenModel != null) {
      onStage(
        AiEnhanceModelInfo(
          realEsrganUpscaleModelSpec.fileName,
          sharpenModel.usingGpu,
          sharpenModel.directMlError,
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
      upscaleSpec: upscaleModelSpec,
      enableDenoise: effectiveEnableDenoise,
      enableUpscale: enableUpscale,
      denoiseStrength: denoiseStrengthPercent / 100.0,
      sharpenUpscale: wantSharpen
          ? (tile) => sharpenModel!.runTile(tile)
          : null,
      sharpenUpscaleSpec: wantSharpen ? realEsrganUpscaleModelSpec : null,
      sharpnessAmount: upscaleSharpnessAmount / 100.0,
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
      rawDenoise: enableRawDenoise,
      denoiseStrengthPercent: denoiseStrengthPercent,
      denoiseModelPath: customDenoiseModelPath,
      upscaleSharpnessAmount: upscaleSharpnessAmount,
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
    this.enableRawDenoise,
    this.denoiseStrengthPercent,
    this.customDenoiseModelPath,
    this.upscaleSharpnessAmount,
    this.sendPort,
  );

  final String path;
  final String cacheDir;
  final int previewMaxDimension;
  final bool enableDenoise;
  final bool enableUpscale;
  final bool enableRawDenoise;
  final int denoiseStrengthPercent;
  final String? customDenoiseModelPath;
  final int upscaleSharpnessAmount;
  final SendPort sendPort;
}

void _aiEnhanceDecodeIsolateEntry(_AiEnhanceDecodeIsolateArgs args) async {
  final result = await _decodeAndEnhance(
    args.path,
    args.cacheDir,
    args.previewMaxDimension,
    args.enableDenoise,
    args.enableUpscale,
    args.enableRawDenoise,
    args.denoiseStrengthPercent,
    args.customDenoiseModelPath,
    args.upscaleSharpnessAmount,
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
  bool enableRawDenoise = false,
  int denoiseStrengthPercent = 100,
  String? customDenoiseModelPath,
  int previewMaxDimension = defaultPreviewMaxDimension,
  AiEnhanceCancellationToken? cancellationToken,
  // See ai_enhance.dart's enhanceImage sharpnessAmount doc — 0 (the
  // default) never loads/runs Real-ESRGAN at all (upscaleModelSpec/DIS
  // alone); any value above 0 blends its output in at that ratio, paying
  // its full inference cost regardless of how small the ratio is. Ignored
  // when [enableUpscale] is false.
  int upscaleSharpnessAmount = 0,
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
      enableRawDenoise,
      denoiseStrengthPercent,
      customDenoiseModelPath,
      upscaleSharpnessAmount,
      receivePort.sendPort,
    ),
  );
  try {
    Future<EditSourcePair?> receiveResult() async {
      await for (final message in receivePort) {
        if (message is RawDecodeStage ||
            message is AiEnhanceModelInfo ||
            message is AiEnhanceProgress ||
            message is CustomDenoiseModelFallback) {
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
