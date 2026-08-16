import 'dart:typed_data';

import 'blur.dart';

/// Mirrors Lightroom Classic's Detail panel Noise Reduction section — same
/// six sliders, same rough intent for each, ported as a classic (non-AI)
/// edge-aware filter rather than a trained denoising model. See
/// [applyDenoise] for how each one maps onto the actual math.
class DenoiseParams {
  const DenoiseParams({
    this.luminance = 0,
    this.luminanceDetail = 50,
    this.luminanceContrast = 0,
    this.color = 0,
    this.colorDetail = 50,
    this.colorSmoothness = 50,
  });

  /// Builds params from the editor's flat `{sliderName: value}` map —
  /// keyed `'Denoise' + <Luminance|LuminanceDetail|LuminanceContrast|
  /// Color|ColorDetail|ColorSmoothness>`, same convention as every other
  /// slider.
  factory DenoiseParams.fromValues(Map<String, double> values) {
    const defaults = DenoiseParams();
    return DenoiseParams(
      luminance: values['DenoiseLuminance'] ?? defaults.luminance,
      luminanceDetail:
          values['DenoiseLuminanceDetail'] ?? defaults.luminanceDetail,
      luminanceContrast:
          values['DenoiseLuminanceContrast'] ?? defaults.luminanceContrast,
      color: values['DenoiseColor'] ?? defaults.color,
      colorDetail: values['DenoiseColorDetail'] ?? defaults.colorDetail,
      colorSmoothness:
          values['DenoiseColorSmoothness'] ?? defaults.colorSmoothness,
    );
  }

  /// 0..100 — overall strength of luminance (brightness) noise reduction.
  final double luminance;

  /// 0..100 — how much fine texture survives the smoothing; higher keeps
  /// more detail (and more residual noise), lower smooths harder.
  final double luminanceDetail;

  /// 0..100 — adds back a little local contrast after smoothing, since
  /// heavy luminance denoising alone tends to look flat/plasticky.
  final double luminanceContrast;

  /// 0..100 — overall strength of color (chroma) noise reduction —
  /// usually the more visually important half of denoising, since color
  /// speckling reads as noisier than luminance grain at the same amount.
  final double color;

  /// 0..100 — how much fine color detail survives, same idea as
  /// [luminanceDetail] but for chroma.
  final double colorDetail;

  /// 0..100 — how smooth (vs. blotchy) the chroma result is; scales the
  /// blur radius directly rather than gating by an edge threshold.
  final double colorSmoothness;

  /// A no-op exactly when both master sliders are 0 — the detail/contrast/
  /// smoothness sub-sliders have nothing to act on until then, matching
  /// Lightroom's own behavior (they're inert with Luminance/Color at 0).
  bool get isIdentity => luminance == 0 && color == 0;
}

/// Applies classic edge-aware noise reduction to packed RGB [img] in
/// place — a no-op when both master sliders are 0.
///
/// Luminance and chroma are denoised independently: luminance from a
/// straight average of R/G/B (matching this file's other per-pixel
/// luminance uses), chroma as each channel's deviation from that
/// luminance. Each gets a fast Gaussian blur (via [gaussianBlurChannel])
/// blended back against the original through an edge-preserving soft
/// threshold — small (noise-scale) deviations get smoothed away, larger
/// ones (real detail/edges) survive close to untouched.
///
/// Designed to run via `compute()`: pure function over simple,
/// isolate-transferable data (same as the rest of render.dart).
void applyDenoise(
  Float32List img,
  int width,
  int height,
  DenoiseParams params,
) {
  if (params.isIdentity) {
    return;
  }
  final pixelCount = width * height;
  final luminance = Float32List(pixelCount);
  final chromaR = Float32List(pixelCount);
  final chromaG = Float32List(pixelCount);
  final chromaB = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final l = (img[i] + img[i + 1] + img[i + 2]) / 3.0;
    luminance[p] = l;
    chromaR[p] = img[i] - l;
    chromaG[p] = img[i + 1] - l;
    chromaB[p] = img[i + 2] - l;
  }

  final denoisedLuminance = params.luminance > 0
      ? _denoiseLuminance(luminance, width, height, params)
      : luminance;
  final denoisedChromaR = params.color > 0
      ? _denoiseChannel(
          chromaR,
          width,
          height,
          params.color,
          params.colorDetail,
          params.colorSmoothness,
        )
      : chromaR;
  final denoisedChromaG = params.color > 0
      ? _denoiseChannel(
          chromaG,
          width,
          height,
          params.color,
          params.colorDetail,
          params.colorSmoothness,
        )
      : chromaG;
  final denoisedChromaB = params.color > 0
      ? _denoiseChannel(
          chromaB,
          width,
          height,
          params.color,
          params.colorDetail,
          params.colorSmoothness,
        )
      : chromaB;

  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final l = denoisedLuminance[p];
    img[i] = l + denoisedChromaR[p];
    img[i + 1] = l + denoisedChromaG[p];
    img[i + 2] = l + denoisedChromaB[p];
  }
}

/// Edge-preserving smooth for one channel: blur it, then blend back toward
/// the original wherever the local high-frequency deviation is large
/// enough to look like real detail rather than noise. [detail] (0..100)
/// lowers that threshold as it rises, so more fine texture survives;
/// [smoothness] (0..100, only meaningful for chroma) additionally widens
/// the blur radius itself for a softer result.
Float32List _denoiseChannel(
  Float32List channel,
  int width,
  int height,
  double amount,
  double detail,
  double smoothness,
) {
  final sigma = 0.6 + (amount / 100.0) * 2.4 + (smoothness / 100.0) * 2.0;
  final blurred = gaussianBlurChannel(channel, width, height, sigma);
  // Highest at detail=0 (aggressively smooths everything), lowest at
  // detail=100 (only smooths near-zero, noise-scale deviations).
  final threshold = 18.0 * (1.0 - detail.clamp(0.0, 100.0) / 100.0) + 1.0;
  final strength = (amount / 100.0).clamp(0.0, 1.0);
  final out = Float32List(channel.length);
  for (var p = 0; p < channel.length; p++) {
    final highFreq = channel[p] - blurred[p];
    final preserve = (highFreq.abs() / threshold).clamp(0.0, 1.0);
    final denoised = blurred[p] + highFreq * preserve;
    out[p] = channel[p] + (denoised - channel[p]) * strength;
  }
  return out;
}

Float32List _denoiseLuminance(
  Float32List luminance,
  int width,
  int height,
  DenoiseParams params,
) {
  var result = _denoiseChannel(
    luminance,
    width,
    height,
    params.luminance,
    params.luminanceDetail,
    0,
  );
  if (params.luminanceContrast > 0) {
    // A small-radius local-contrast boost on the smoothed result, to
    // counter the flat/plasticky look heavy luminance denoising leaves —
    // same technique as Clarity (see local_contrast.dart), just folded in
    // here instead of pulling that file in as a dependency for one call.
    final blurred = gaussianBlurChannel(result, width, height, 4);
    final factor = params.luminanceContrast / 100.0;
    final boosted = Float32List(result.length);
    for (var p = 0; p < result.length; p++) {
      boosted[p] = result[p] + (result[p] - blurred[p]) * factor;
    }
    result = boosted;
  }
  return result;
}
