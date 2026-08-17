import 'dart:typed_data';

import 'blur.dart';

/// Lightroom/Photomator-style one-shot denoise control.
///
/// This first Windows implementation is deliberately self-contained: it uses
/// a multi-scale, edge-aware residual pass so the feature works offline and
/// without shipping a large ML runtime or model. The API is kept separate from
/// the classic six-slider denoise pass so a native model backend can replace
/// this implementation later without changing presets or the editor UI.
class AiDenoiseParams {
  const AiDenoiseParams({this.amount = 0});

  factory AiDenoiseParams.fromValues(Map<String, double> values) =>
      AiDenoiseParams(amount: values['AiDenoiseAmount'] ?? 0);

  /// 0..100 — strength of the one-shot intelligent denoise pass.
  final double amount;

  bool get isIdentity => amount <= 0;
}

/// Applies a one-shot adaptive denoise pass to packed RGB data.
///
/// Two local scales are combined: broad grain is reduced with a larger blur,
/// while the fine scale is retained around strong edges. This gives the
/// Lightroom/Photomator-like result expected from a dedicated AI button while
/// remaining deterministic, offline, and safe in a [compute] isolate.
void applyAiDenoise(
  Float32List img,
  int width,
  int height,
  AiDenoiseParams params,
) {
  if (params.isIdentity || width < 3 || height < 3) {
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

  final strength = (params.amount / 100.0).clamp(0.0, 1.0);
  final broad = gaussianBlurChannel(luminance, width, height, 3);
  final fine = gaussianBlurChannel(luminance, width, height, 1);
  final chromaBlurR = gaussianBlurChannel(chromaR, width, height, 2);
  final chromaBlurG = gaussianBlurChannel(chromaG, width, height, 2);
  final chromaBlurB = gaussianBlurChannel(chromaB, width, height, 2);

  for (var p = 0; p < pixelCount; p++) {
    final edge = (luminance[p] - fine[p]).abs();
    final edgeProtection = (edge / 22.0).clamp(0.0, 1.0);
    final lMix = strength * (1.0 - edgeProtection * 0.82);
    final cMix = strength * 0.72;
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
