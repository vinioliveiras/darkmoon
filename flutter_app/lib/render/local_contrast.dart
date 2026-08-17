import 'dart:typed_data';

import 'blur.dart';
import 'luminance.dart';

/// Boosts (or reduces) local luminance detail by adding back a fraction of
/// `luminance - blur(luminance)` — a classic unsharp-mask-style local
/// contrast effect. Used for both Texture (small [sigma], [noiseAware] true)
/// and Clarity (large [sigma], [protectMidtones] true so flat skin/sky areas
/// aren't dragged around as hard as edges).
///
/// The adjustment is intentionally luminance-only: Texture/Clarity should not
/// independently sharpen R, G and B channels, because that boosts chroma noise
/// right alongside real fine detail. This mirrors Lightroom's behavior more
/// closely while preserving color stability in noisy shadows.
void applyLocalContrast(
  Float32List img,
  int width,
  int height,
  double amount,
  double sigma, {
  bool protectMidtones = false,
  bool noiseAware = false,
}) {
  if (amount == 0) {
    return;
  }
  final pixelCount = width * height;
  final luminance = Float32List(pixelCount);
  extractLuminance(img, luminance);

  Float32List? weight;
  if (protectMidtones) {
    weight = Float32List(pixelCount);
    for (var p = 0; p < pixelCount; p++) {
      final normalizedLuma = luminance[p] / 255.0;
      weight[p] = (1.0 - (normalizedLuma - 0.5).abs() * 2.0).clamp(0.15, 1.0);
    }
  }

  final factor = amount / 100.0;
  final blurred = gaussianBlurChannel(luminance, width, height, sigma);
  Float32List? localNoiseVar;
  if (noiseAware) {
    final residualSq = Float32List(pixelCount);
    for (var p = 0; p < pixelCount; p++) {
      final residual = luminance[p] - blurred[p];
      residualSq[p] = residual * residual;
    }
    localNoiseVar = localVarianceFromResidualSq(residualSq, width, height, 6);
  }

  final delta = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    var highFreq = luminance[p] - blurred[p];
    if (protectMidtones) {
      highFreq *= weight![p];
    }
    var gain = factor;
    if (localNoiseVar != null) {
      final rSq = highFreq * highFreq;
      gain *= rSq / (rSq + localNoiseVar[p] + 1.0);
    }
    delta[p] = highFreq * gain;
  }
  applyLuminanceDelta(img, delta);
}
