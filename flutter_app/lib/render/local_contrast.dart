import 'dart:typed_data';

import 'blur.dart';
import 'luminance.dart';

/// Selective Clarity (2026-09-13, PENDING 47 — Photomator's): extra local
/// contrast for each tonal band on top of [applyLocalContrast]'s global
/// `amount`, in the same units (slider value times the stage's strength).
/// A pixel's band weights come from its luminance: shadows fade out from
/// 25% to 50%, highlights fade in from 50% to 75%, midtones are the rest —
/// see [tonalBandWeights]. The GPU's local_contrast_combine.frag mirrors
/// both.
class TonalAmounts {
  const TonalAmounts({
    this.shadows = 0,
    this.midtones = 0,
    this.highlights = 0,
  });

  final double shadows;
  final double midtones;
  final double highlights;

  bool get isZero => shadows == 0 && midtones == 0 && highlights == 0;
}

double _smoothstep(double e0, double e1, double x) {
  final t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// How much of the shadows, midtones and highlights bands a pixel of
/// [normalizedLuma] (0..1) belongs to; the three sum to 1.
(double shadows, double midtones, double highlights) tonalBandWeights(
  double normalizedLuma,
) {
  final s = 1.0 - _smoothstep(0.25, 0.5, normalizedLuma);
  final h = _smoothstep(0.5, 0.75, normalizedLuma);
  return (s, (1.0 - s - h).clamp(0.0, 1.0), h);
}

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
/// instead of smoothing it — see [calClarityEdgeThreshold]. [rowOffset]
/// is for that base's downsampled fit when [img] is one band of a larger
/// frame — see [guidedSmoothChannel].
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
  int rowOffset = 0,
  TonalAmounts tonal = const TonalAmounts(),
}) {
  if (amount == 0 && tonal.isZero) {
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
          rowOffset: rowOffset,
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
  final selective = !tonal.isZero;
  for (var p = 0; p < pixelCount; p++) {
    var highFreq = luminance[p] - blurred[p];
    if (protectMidtones) {
      highFreq *= weight![p];
    }
    var gain = factor;
    if (selective) {
      final (ws, wm, wh) = tonalBandWeights(luminance[p] / 255.0);
      gain +=
          (tonal.shadows * ws + tonal.midtones * wm + tonal.highlights * wh) /
          100.0;
    }
    if (localNoiseVar != null) {
      final rSq = highFreq * highFreq;
      gain *= rSq / (rSq + localNoiseVar[p] + 1.0);
    }
    delta[p] = highFreq * gain;
  }
  applyLuminanceDelta(img, delta);
}
