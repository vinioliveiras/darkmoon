import 'dart:typed_data';

import 'ai_denoise_tiling.dart';
import '../native/onnx_runtime.dart';

/// Result of [enhanceImage] — packed, row-major, 3 bytes/pixel (0-255)
/// RGB, at the *upscaled* dimensions ([width]/[height] already reflect
/// [enhanceImage]'s own `upscaleSpec` argument's scale factor, not the
/// original decode size).
class AiEnhanceResult {
  const AiEnhanceResult({
    required this.rgbBytes,
    required this.width,
    required this.height,
  });

  final Uint8List rgbBytes;
  final int width;
  final int height;
}

/// The AI Enhance pipeline (item 13, distinct from the classical
/// `applyAiDenoise` render-pipeline stage): reconstructive
/// denoise (removes noise *and* film grain, recovers texture the noise was
/// masking) and/or 2x super-resolution, run independently —
/// [enableDenoise]/[enableUpscale] let a caller ask for either pass alone
/// (denoise a noisy JPEG without changing its resolution, or upscale an
/// already-clean photo without paying for a denoise pass it doesn't need)
/// as well as both together. When both are on, denoise still runs first,
/// on the *original* buffer, so the upscaler isn't asked to faithfully
/// enlarge noise into more pixels.
///
/// [denoise]/[upscale] are the two models' `OnnxModel.runTile` (or a fake,
/// for testing the tiling/ordering/progress-forwarding logic here without
/// touching real hardware — same dependency-injection shape
/// `ai_denoise_tiling.dart`'s own `denoiseTiled` already uses) — this
/// function itself has no FFI/native dependency, just orchestrates up to
/// two [denoiseTiled] passes. Always required even when the corresponding
/// `enable*` flag is false, since callers already have both models loaded
/// by the time they call this — simpler than making them nullable for a
/// call shape that's only ever hit from one place.
///
/// [upscaleSpec] picks the upscale pass's tile geometry (`upscaleModelSpec`
/// — DIS, fast/fidelity-first) — the caller must pass whichever one
/// [upscale] was actually bound to, so tiling matches the model. Ignored
/// when [enableUpscale] is false.
///
/// [sharpenUpscale]/[sharpenUpscaleSpec]/[sharpnessAmount] blend in a
/// second, slower upscale model (`realEsrganUpscaleModelSpec` — GAN-
/// trained, synthesizes more plausible high-frequency detail than DIS's
/// fidelity-first result; see that constant's own doc) on top of
/// [upscale]'s output — same "fixed model, blend afterward for strength"
/// shape as [denoiseStrength] above, since Real-ESRGAN has no strength
/// input of its own either. [sharpnessAmount] 0.0 (default) never runs
/// [sharpenUpscale] at all, so a caller that leaves it off pays zero extra
/// cost — this is a real, not gradual, cost cliff: any [sharpnessAmount]
/// above 0.0 pays [sharpenUpscale]'s full inference cost (~3.5 min for a
/// 24MP photo on a real GPU, vs. a few seconds for DIS alone), the *blend
/// ratio* doesn't reduce that. 1.0 is [sharpenUpscale]'s raw output,
/// unblended. Both [upscale] and [sharpenUpscale] must share the same
/// [OnnxModelSpec.scaleFactor] (both bundled models are 2x) so their
/// outputs are the same size to blend.
///
/// [detailRestore]/[detailSharpen]/[detailSpec]/[detailAmount] chain a
/// second same-resolution pair (GaterV3 restore-then-sharpen,
/// `gaterV3RestoreModelSpec`/`gaterV3SharpenModelSpec` — found
/// researching item 35's combo follow-up, 2026-08-31) on top of
/// [denoise]'s output, before the optional upscale pass — same "toggle
/// always pairs with an Amount blend, defaulting to a balanced middle
/// value" convention as [denoiseStrength], per explicit user direction:
/// unlike [sharpnessAmount] (a real cost-cliff, since Real-ESRGAN alone
/// costs ~3.5 min/24MP-photo), GaterV3's pair is cheap (~2s combined on
/// a 700x700 crop, faster than [denoise] itself) so there's no reason to
/// gate it behind "0 = never runs" — [detailAmount] 0.0 still runs both
/// models, just blends fully back to [denoise]'s own output.
///
/// [rgbBytes] is packed, row-major, 3 bytes/pixel (0-255) — the same
/// convention `render.dart`'s buffers use before their own internal
/// 0..1-normalized processing. Blocking (runs potentially thousands of
/// tile inferences); callers must run this on a background isolate.
AiEnhanceResult enhanceImage(
  Uint8List rgbBytes,
  int width,
  int height, {
  required Float32List Function(Float32List tile) denoise,
  required Float32List Function(Float32List tile) upscale,
  OnnxModelSpec upscaleSpec = upscaleModelSpec,
  bool enableDenoise = true,
  bool enableUpscale = true,
  Float32List Function(Float32List tile)? detailRestore,
  Float32List Function(Float32List tile)? detailSharpen,
  OnnxModelSpec? detailSpec,
  double detailAmount = 0.0,
  // The bundled denoise model is a fixed, blind denoiser — it has no built-in strength
  // knob (unlike e.g. FFDNet-style models that take a noise-level map as
  // an extra input channel), so "how strong" can only be controlled
  // afterward: linearly blending its full-strength output back toward
  // the original at [denoiseStrength] (1.0 = the model's raw output,
  // untouched; 0.0 = pure original, i.e. no denoise at all). Ignored
  // when [enableDenoise] is false. Blending happens *before* the
  // optional upscale pass, same reasoning as running denoise before
  // upscale in the first place — the upscaler should never see more
  // noise than the user actually asked to keep.
  double denoiseStrength = 1.0,
  Float32List Function(Float32List tile)? sharpenUpscale,
  OnnxModelSpec? sharpenUpscaleSpec,
  double sharpnessAmount = 0.0,
  void Function(String stage, int tileIndex, int totalTiles)? onProgress,
}) {
  final floatRgb = Float32List(rgbBytes.length);
  for (var i = 0; i < rgbBytes.length; i++) {
    floatRgb[i] = rgbBytes[i] / 255.0;
  }

  Float32List denoised;
  if (enableDenoise) {
    denoised = denoiseTiled(
      floatRgb,
      width,
      height,
      inputTileSize: denoiseModelSpec.inputTileSize,
      overlap: denoiseModelSpec.inputTileSize ~/ 8,
      scaleFactor: denoiseModelSpec.scaleFactor,
      processTile: denoise,
      onProgress: (i, total) => onProgress?.call('denoise', i, total),
    );
    if (denoiseStrength < 1.0) {
      final strength = denoiseStrength.clamp(0.0, 1.0);
      for (var i = 0; i < denoised.length; i++) {
        denoised[i] = floatRgb[i] + (denoised[i] - floatRgb[i]) * strength;
      }
    }
  } else {
    denoised = floatRgb;
  }

  if (detailRestore != null && detailSharpen != null && detailSpec != null) {
    final restored = denoiseTiled(
      denoised,
      width,
      height,
      inputTileSize: detailSpec.inputTileSize,
      overlap: detailSpec.inputTileSize ~/ 8,
      scaleFactor: detailSpec.scaleFactor,
      processTile: detailRestore,
      onProgress: (i, total) => onProgress?.call('detail-restore', i, total),
    );
    final detailed = denoiseTiled(
      restored,
      width,
      height,
      inputTileSize: detailSpec.inputTileSize,
      overlap: detailSpec.inputTileSize ~/ 8,
      scaleFactor: detailSpec.scaleFactor,
      processTile: detailSharpen,
      onProgress: (i, total) => onProgress?.call('detail-sharpen', i, total),
    );
    final amount = detailAmount.clamp(0.0, 1.0);
    final blended = Float32List(denoised.length);
    for (var i = 0; i < denoised.length; i++) {
      blended[i] = denoised[i] + (detailed[i] - denoised[i]) * amount;
    }
    denoised = blended;
  }

  var upscaled = enableUpscale
      ? denoiseTiled(
          denoised,
          width,
          height,
          inputTileSize: upscaleSpec.inputTileSize,
          overlap: upscaleSpec.inputTileSize ~/ 8,
          scaleFactor: upscaleSpec.scaleFactor,
          processTile: upscale,
          onProgress: (i, total) => onProgress?.call('upscale', i, total),
        )
      : denoised;

  final amount = sharpnessAmount.clamp(0.0, 1.0);
  if (enableUpscale &&
      amount > 0.0 &&
      sharpenUpscale != null &&
      sharpenUpscaleSpec != null) {
    final sharpened = denoiseTiled(
      denoised,
      width,
      height,
      inputTileSize: sharpenUpscaleSpec.inputTileSize,
      overlap: sharpenUpscaleSpec.inputTileSize ~/ 8,
      scaleFactor: sharpenUpscaleSpec.scaleFactor,
      processTile: sharpenUpscale,
      onProgress: (i, total) => onProgress?.call('sharpen', i, total),
    );
    final blended = Float32List(upscaled.length);
    for (var i = 0; i < upscaled.length; i++) {
      blended[i] = upscaled[i] + (sharpened[i] - upscaled[i]) * amount;
    }
    upscaled = blended;
  }

  final scaleFactor = enableUpscale ? upscaleSpec.scaleFactor : 1;
  final outWidth = width * scaleFactor;
  final outHeight = height * scaleFactor;
  final outBytes = Uint8List(upscaled.length);
  for (var i = 0; i < upscaled.length; i++) {
    outBytes[i] = (upscaled[i] * 255.0).clamp(0, 255).round();
  }

  return AiEnhanceResult(
    rgbBytes: outBytes,
    width: outWidth,
    height: outHeight,
  );
}
