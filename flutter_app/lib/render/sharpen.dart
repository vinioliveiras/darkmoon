import 'dart:typed_data';

import 'blur.dart';

/// Mirrors Lightroom Classic's Detail panel Sharpening section — same four
/// sliders, same rough intent for each, as a classic unsharp-mask filter
/// rather than Lightroom's proprietary deconvolution-based sharpener. See
/// [applySharpen] for how each one maps onto the actual math.
class SharpenParams {
  const SharpenParams({
    this.amount = 0,
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
      detail: values['SharpenDetail'] ?? defaults.detail,
      masking: values['SharpenMasking'] ?? defaults.masking,
    );
  }

  /// 0..150 — overall strength of the sharpening effect.
  final double amount;

  /// 0.5..3.0 — size of the edge detail being emphasized; matches the
  /// Gaussian blur sigma of the underlying unsharp mask.
  final double radius;

  /// 0..100 — how much very fine (high-frequency) texture is emphasized
  /// alongside broader edges; higher pulls in more fine detail.
  final double detail;

  /// 0..100 — restricts sharpening to strong edges, protecting smooth
  /// areas (skies, skin) from being sharpened along with real detail.
  final double masking;

  /// A no-op exactly when [amount] is 0 — the other sliders have nothing
  /// to act on until then, matching Lightroom's own behavior.
  bool get isIdentity => amount == 0;
}

/// Applies classic unsharp-mask sharpening to packed RGB [img] in place —
/// a no-op when [SharpenParams.amount] is 0.
///
/// Works on luminance only (not each RGB channel independently) so the
/// effect emphasizes edges without introducing color fringing: blur the
/// luminance, take the high-frequency residual (original minus blurred),
/// then add a masked, detail-weighted fraction of that residual back onto
/// all three channels equally.
///
/// Designed to run via `compute()`: pure function over simple, isolate-
/// transferable data (same as the rest of render.dart).
void applySharpen(
  Float32List img,
  int width,
  int height,
  SharpenParams params,
) {
  if (params.isIdentity) {
    return;
  }
  final pixelCount = width * height;
  final luminance = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    luminance[p] = (img[i] + img[i + 1] + img[i + 2]) / 3.0;
  }

  final sigma = params.radius.clamp(0.5, 3.0);
  final blurred = gaussianBlurChannel(luminance, width, height, sigma);

  // A second, wider blur of the high-frequency residual's magnitude
  // approximates "how edge-like" each neighborhood is — used to fade the
  // effect out over smooth regions as masking increases, without a hard
  // per-pixel cutoff that would look artificial.
  final highFreq = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    highFreq[p] = luminance[p] - blurred[p];
  }
  final edgeStrength = params.masking > 0
      ? gaussianBlurChannel(
          Float32List.fromList([for (final v in highFreq) v.abs()]),
          width,
          height,
          sigma * 2,
        )
      : null;

  // Detail biases the residual toward finer texture: at detail=0 only the
  // coarse (radius-scale) residual survives; at detail=100 a sharper,
  // finer-grained residual (from a narrower blur) is blended in too.
  final fineBlurred = params.detail > 0
      ? gaussianBlurChannel(luminance, width, height, sigma * 0.35)
      : null;

  final strength = params.amount / 100.0;
  final maskAmount = params.masking / 100.0;
  // Edge strength values in the 2..10 range separate real edges from flat
  // noise-scale variation at typical preview resolutions/exposures.
  const maskThreshold = 6.0;

  for (var p = 0; p < pixelCount; p++) {
    var residual = highFreq[p];
    if (fineBlurred != null) {
      final fineResidual = luminance[p] - fineBlurred[p];
      final detailMix = params.detail / 100.0;
      residual = residual * (1 - detailMix * 0.6) + fineResidual * detailMix;
    }
    var factor = strength;
    if (edgeStrength != null) {
      final edge = (edgeStrength[p] / maskThreshold).clamp(0.0, 1.0);
      factor *= 1.0 - maskAmount * (1.0 - edge);
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
