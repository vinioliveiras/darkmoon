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
/// right alongside real fine detail. This mirrors Meridian's behavior more
/// closely while preserving color stability in noisy shadows.
///
/// [edgeThreshold] > 0 swaps the Gaussian base for the edge-preserving
/// [guidedSmoothChannel] (Clarity, 2026-09-10): a wide Gaussian averages
/// across every strong edge, and boosting the resulting over/undershoot is
/// exactly the halo Clarity was known for. The threshold is the local mean
/// absolute deviation (0-255) above which the base follows the image
/// instead of smoothing it — see [calClarityEdgeThreshold].
void applyLocalContrast(
  Float32List img,
  int width,
  int height,
  double amount,
  double sigma, {
  bool protectMidtones = false,
  bool noiseAware = false,
  int noiseRadius = 6,
  double edgeThreshold = 0,
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
  final blurred = edgeThreshold > 0
      ? guidedSmoothChannel(
          luminance,
          width,
          height,
          guidedRadiusForSigma(sigma),
          edgeThreshold,
        )
      : gaussianBlurChannel(luminance, width, height, sigma);
  Float32List? localNoiseVar;
  if (noiseAware) {
    final residualSq = Float32List(pixelCount);
    for (var p = 0; p < pixelCount; p++) {
      final residual = luminance[p] - blurred[p];
      residualSq[p] = residual * residual;
    }
    localNoiseVar = localVarianceFromResidualSq(
      residualSq,
      width,
      height,
      noiseRadius,
    );
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
