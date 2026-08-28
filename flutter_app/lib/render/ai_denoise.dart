import 'dart:typed_data';

import 'blur.dart';
import 'calibration.dart';
import 'luminance.dart';

/// One-shot, Lightroom/Photomator-style intelligent denoise pass — no
/// sliders, no manual tuning: each level is pre-tuned to what testing found
/// to be a good noise/detail trade-off for that strength, so picking a
/// level is the only decision the user makes.
enum AiDenoiseLevel { light, medium, strong }

/// Public (not `_AiDenoiseTuning`) so the GPU render path
/// (`lib/render/gpu/denoise_gpu.dart`) can reuse [aiDenoiseTuning]'s exact
/// per-level values for its own uniforms instead of duplicating them and
/// risking drift.
class AiDenoiseTuning {
  const AiDenoiseTuning({
    required this.lumaSigma,
    required this.lumaStrength,
    required this.chromaSigma,
    required this.chromaStrength,
  });

  /// Blur radius (px) the luminance noise floor is measured/smoothed over.
  final double lumaSigma;

  /// 0..1 — overall luminance smoothing amount.
  final double lumaStrength;

  /// Blur radius (px) for chroma — wider than luma, since color noise is
  /// lower-frequency and less detail-bearing than luminance grain.
  final double chromaSigma;

  /// 0..1 — overall chroma smoothing amount.
  final double chromaStrength;
}

const aiDenoiseTuning = {
  AiDenoiseLevel.light: AiDenoiseTuning(
    lumaSigma: 1.4,
    lumaStrength: 0.35,
    chromaSigma: 3.0,
    chromaStrength: 0.45,
  ),
  AiDenoiseLevel.medium: AiDenoiseTuning(
    lumaSigma: 2.0,
    lumaStrength: 0.55,
    chromaSigma: 4.0,
    chromaStrength: 0.65,
  ),
  AiDenoiseLevel.strong: AiDenoiseTuning(
    lumaSigma: 2.8,
    lumaStrength: 0.7,
    chromaSigma: 5.0,
    chromaStrength: 0.8,
  ),
};

class AiDenoiseParams {
  const AiDenoiseParams({this.level});

  /// Builds params from the editor's flat `{sliderName: value}` map — a
  /// single `'AiDenoiseLevel'` key (1/2/3 for Light/Medium/Strong), absent
  /// or below 1 meaning off. Not a slider: applied as a one-shot action
  /// from the toolbar's AI Denoise dialog rather than dragged.
  factory AiDenoiseParams.fromValues(Map<String, double> values) {
    final raw = values['AiDenoiseLevel'];
    if (raw == null || raw < 1) {
      return const AiDenoiseParams();
    }
    final index = raw.round().clamp(1, AiDenoiseLevel.values.length) - 1;
    return AiDenoiseParams(level: AiDenoiseLevel.values[index]);
  }

  final AiDenoiseLevel? level;

  bool get isIdentity => level == null;
}

/// Applies the one-shot adaptive denoise pass to packed RGB data.
///
/// Luminance and chroma are denoised independently via
/// [adaptiveDenoiseChannel]'s locally-calibrated noise-floor estimate,
/// rather than a single fixed edge-magnitude cutoff — so smoothing scales
/// with each region's own actual noise level instead of either flattening
/// low-noise areas or leaving noisier ones under-treated. Deterministic and
/// fully offline: no model to ship, safe to run in a `compute()` isolate.
///
/// Runs early in the render pipeline (right after white balance/exposure,
/// before tone shaping) so later adjustments that lift shadows or push
/// local contrast don't amplify noise this pass never got a chance to
/// remove — matching how Lightroom's own noise reduction happens before
/// tone/presence adjustments rather than after them.
void applyAiDenoise(
  Float32List img,
  int width,
  int height,
  AiDenoiseParams params,
) {
  final level = params.level;
  if (level == null || width < 3 || height < 3) {
    return;
  }
  final tuning = aiDenoiseTuning[level]!;
  // calibration.dart global scale on top of the per-level table.
  final lumaStrength =
      (tuning.lumaStrength * calDenoiseLumaStrengthScale).clamp(0.0, 1.0);
  final chromaStrength =
      (tuning.chromaStrength * calDenoiseChromaStrengthScale).clamp(0.0, 1.0);
  final pixelCount = width * height;
  final luminance = Float32List(pixelCount);
  final chromaR = Float32List(pixelCount);
  final chromaG = Float32List(pixelCount);
  final chromaB = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final l = luminanceRgb(img[i], img[i + 1], img[i + 2]);
    luminance[p] = l;
    chromaR[p] = img[i] - l;
    chromaG[p] = img[i + 1] - l;
    chromaB[p] = img[i + 2] - l;
  }

  final denoisedLuma = adaptiveDenoiseChannel(
    luminance,
    width,
    height,
    tuning.lumaSigma,
    lumaStrength,
  );
  final denoisedR = adaptiveDenoiseChannel(
    chromaR,
    width,
    height,
    tuning.chromaSigma,
    chromaStrength,
  );
  final denoisedG = adaptiveDenoiseChannel(
    chromaG,
    width,
    height,
    tuning.chromaSigma,
    chromaStrength,
  );
  final denoisedB = adaptiveDenoiseChannel(
    chromaB,
    width,
    height,
    tuning.chromaSigma,
    chromaStrength,
  );

  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final l = denoisedLuma[p];
    img[i] = (l + denoisedR[p]).clamp(0.0, 255.0);
    img[i + 1] = (l + denoisedG[p]).clamp(0.0, 255.0);
    img[i + 2] = (l + denoisedB[p]).clamp(0.0, 255.0);
  }
}
