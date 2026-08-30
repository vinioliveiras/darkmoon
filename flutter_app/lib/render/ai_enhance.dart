import 'dart:typed_data';

import 'ai_denoise_tiling.dart';
import '../native/onnx_runtime.dart';

/// Result of [enhanceImage] — packed, row-major, 3 bytes/pixel (0-255)
/// RGB, at the *upscaled* dimensions ([width]/[height] already reflect
/// [upscaleModelSpec]'s scale factor, not the original decode size).
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
/// `applyAiDenoise` render-pipeline stage): NAFNet-SIDD reconstructive
/// denoise (removes noise *and* film grain, recovers texture the noise was
/// masking) and/or Real-ESRGAN 2x super-resolution, run independently —
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
  bool enableDenoise = true,
  bool enableUpscale = true,
  void Function(String stage, int tileIndex, int totalTiles)? onProgress,
}) {
  final floatRgb = Float32List(rgbBytes.length);
  for (var i = 0; i < rgbBytes.length; i++) {
    floatRgb[i] = rgbBytes[i] / 255.0;
  }

  final denoised = enableDenoise
      ? denoiseTiled(
          floatRgb,
          width,
          height,
          inputTileSize: denoiseModelSpec.inputTileSize,
          overlap: denoiseModelSpec.inputTileSize ~/ 8,
          scaleFactor: denoiseModelSpec.scaleFactor,
          processTile: denoise,
          onProgress: (i, total) => onProgress?.call('denoise', i, total),
        )
      : floatRgb;

  final upscaled = enableUpscale
      ? denoiseTiled(
          denoised,
          width,
          height,
          inputTileSize: upscaleModelSpec.inputTileSize,
          overlap: upscaleModelSpec.inputTileSize ~/ 8,
          scaleFactor: upscaleModelSpec.scaleFactor,
          processTile: upscale,
          onProgress: (i, total) => onProgress?.call('upscale', i, total),
        )
      : denoised;

  final scaleFactor = enableUpscale ? upscaleModelSpec.scaleFactor : 1;
  final outWidth = width * scaleFactor;
  final outHeight = height * scaleFactor;
  final outBytes = Uint8List(upscaled.length);
  for (var i = 0; i < upscaled.length; i++) {
    outBytes[i] = (upscaled[i] * 255.0).clamp(0, 255).round();
  }

  return AiEnhanceResult(rgbBytes: outBytes, width: outWidth, height: outHeight);
}
