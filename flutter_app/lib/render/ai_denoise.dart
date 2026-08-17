import 'dart:typed_data';

import 'blur.dart';

/// One-shot, Lightroom/Photomator-style intelligent denoise pass — no
/// sliders, no manual tuning: each level is pre-tuned to what testing found
/// to be a good noise/detail trade-off for that strength, so picking a
/// level is the only decision the user makes.
enum AiDenoiseLevel { light, medium, strong }

class _AiDenoiseTuning {
  const _AiDenoiseTuning({required this.strength, required this.edgeGuard});

  /// 0..1 — how much of the smoothed result replaces the original.
  final double strength;

  /// 0..1 — how strongly real edges are protected from smoothing; higher
  /// keeps more detail/sharpness at the cost of leaving a little more noise
  /// right at edges, which reads as more natural than a uniformly mushy
  /// result.
  final double edgeGuard;
}

const _tuning = {
  AiDenoiseLevel.light: _AiDenoiseTuning(strength: 0.35, edgeGuard: 0.88),
  AiDenoiseLevel.medium: _AiDenoiseTuning(strength: 0.6, edgeGuard: 0.82),
  AiDenoiseLevel.strong: _AiDenoiseTuning(strength: 0.85, edgeGuard: 0.7),
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
/// Two local scales are combined: broad grain is reduced with a wider
/// blur, while a narrower one stands in for untouched fine detail — blended
/// back in more heavily near real edges (per [_AiDenoiseTuning.edgeGuard])
/// so texture and sharpness survive. Deterministic and fully offline: no
/// model to ship, safe to run in a `compute()` isolate.
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
  final tuning = _tuning[level]!;
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

  final broad = gaussianBlurChannel(luminance, width, height, 3);
  final fine = gaussianBlurChannel(luminance, width, height, 1);
  final chromaBlurR = gaussianBlurChannel(chromaR, width, height, 2.2);
  final chromaBlurG = gaussianBlurChannel(chromaG, width, height, 2.2);
  final chromaBlurB = gaussianBlurChannel(chromaB, width, height, 2.2);

  final strength = tuning.strength;
  final cMix = strength * 0.75;
  for (var p = 0; p < pixelCount; p++) {
    final edge = (luminance[p] - fine[p]).abs();
    final edgeProtection = (edge / 22.0).clamp(0.0, 1.0);
    final lMix = strength * (1.0 - edgeProtection * tuning.edgeGuard);
    final l =
        luminance[p] * (1 - lMix) + (broad[p] * 0.65 + fine[p] * 0.35) * lMix;
    final i = p * 3;
    img[i] = (l + chromaR[p] * (1 - cMix) + chromaBlurR[p] * cMix).clamp(
      0.0,
      255.0,
    );
    img[i + 1] = (l + chromaG[p] * (1 - cMix) + chromaBlurG[p] * cMix).clamp(
      0.0,
      255.0,
    );
    img[i + 2] = (l + chromaB[p] * (1 - cMix) + chromaBlurB[p] * cMix).clamp(
      0.0,
      255.0,
    );
  }
}
