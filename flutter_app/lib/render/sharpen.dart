import 'dart:typed_data';

import 'blur.dart';
import 'luminance.dart';

/// Mirrors Lightroom Classic's Detail panel Sharpening section — same four
/// sliders, same rough intent for each, as a classic unsharp-mask filter
/// rather than Lightroom's proprietary deconvolution-based sharpener. See
/// [applySharpen] for how each one maps onto the actual math.
class SharpenParams {
  const SharpenParams({
    // Matches editor_screen.dart's 'SharpenAmount' _SliderSpec default (40,
    // Lightroom's own RAW-import default) — kept in sync so the Before/After
    // "neutral params" preview (_loadNeutralPreview) shows the same
    // baseline sharpen as a freshly-opened, untouched photo.
    this.amount = 40,
    this.radius = 1.0,
    this.detail = 25,
    this.masking = 0,
  });

  /// Builds params from the editor's flat `{sliderName: value}` map —
  /// keyed `'Sharpen' + <Amount|Radius|Detail|Masking>`, same convention
  /// as every other slider.
  factory SharpenParams.fromValues(Map<String, double> values) {
    const defaults = SharpenParams();
    return SharpenParams(
      amount: values['SharpenAmount'] ?? defaults.amount,
      radius: values['SharpenRadius'] ?? defaults.radius,
      detail: values['SharpenDetail']?.round() ?? defaults.detail,
      masking: values['SharpenMasking']?.round() ?? defaults.masking,
    );
  }

  /// Overall sharpening strength (0..150, 0 = off).
  final double amount;

  /// Blur radius in pixels for the base unsharp mask (0.5..3.0).
  final double radius;

  /// How much of the finer high-frequency detail to blend in (0..100).
  final int detail;

  /// Edge-mask threshold: higher = sharpen only stronger edges (0..100).
  final int masking;

  bool get isIdentity => amount == 0;
}

/// Applies luminance-only unsharp masking with optional edge masking.
///
/// The filter computes Rec.709 luminance, builds a blurred version, and
/// sharpens by adding back a fraction of the high-frequency residual.
/// When [params.masking] > 0, a local edge-strength estimate suppresses
/// sharpening in flat/noisy regions (where `edgeStrength` is near the
/// noise floor). This avoids amplifying sensor noise the way a plain
/// unsharp mask does. The result is added equally to R, G, B to keep
/// chroma stable.
void applySharpen(
  Float32List img,
  int width,
  int height,
  SharpenParams params,
) {
  if (params.isIdentity || width < 3 || height < 3) {
    return;
  }
  final pixelCount = width * height;
  final luminance = Float32List(pixelCount);
  extractLuminance(img, luminance);

  final sigma = params.radius.clamp(0.5, 3.0);
  final strength = params.amount / 100.0;
  final maskAmount = params.masking / 100.0;

  final blurred = gaussianBlurChannel(luminance, width, height, sigma);
  final highFreq = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    highFreq[p] = luminance[p] - blurred[p];
  }

  // Optional fine-residual blend for Detail > 0.
  Float32List? fineBlurred;
  if (params.detail > 0) {
    fineBlurred = gaussianBlurChannel(luminance, width, height, sigma * 0.5);
  }

  // Edge strength for masking: blurred absolute high-freq.
  Float32List? edgeStrength;
  if (maskAmount > 0) {
    edgeStrength = Float32List(pixelCount);
    for (var p = 0; p < pixelCount; p++) {
      edgeStrength[p] = highFreq[p].abs();
    }
    edgeStrength = gaussianBlurChannel(edgeStrength, width, height, sigma);
  }

  // Local noise variance for edge-aware masking (reuses blur.dart helper).
  Float32List? localNoiseVar;
  if (maskAmount > 0) {
    final residualSq = Float32List(pixelCount);
    for (var p = 0; p < pixelCount; p++) {
      residualSq[p] = highFreq[p] * highFreq[p];
    }
    localNoiseVar = localVarianceFromResidualSq(residualSq, width, height, 6);
  }

  const edgeThreshold =
      6.0; // 0-255 scale: edge magnitude above which we treat as real
  const edgeThresholdVar = edgeThreshold * edgeThreshold;
  for (var p = 0; p < pixelCount; p++) {
    var residual = highFreq[p];
    if (fineBlurred != null) {
      final fineResidual = luminance[p] - fineBlurred[p];
      final detailMix = params.detail / 100.0;
      residual = residual * (1 - detailMix * 0.6) + fineResidual * detailMix;
    }
    var factor = strength;
    if (edgeStrength != null && localNoiseVar != null) {
      final edge = edgeStrength[p];
      // Soft threshold: if edge is well above local noise floor, keep it;
      // if it's near the floor, suppress sharpening there.
      final edgeSq = edge * edge;
      final noiseFloor = localNoiseVar[p];
      final edgeWeight = edgeSq / (edgeSq + noiseFloor + edgeThresholdVar);
      factor *= 1.0 - maskAmount * (1.0 - edgeWeight);
    }
    final delta = residual * factor;
    if (delta == 0) {
      continue;
    }
    final i = p * 3;
    img[i] += delta;
    img[i + 1] += delta;
    img[i + 2] += delta;
  }
}
