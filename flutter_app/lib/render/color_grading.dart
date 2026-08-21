import 'dart:typed_data';

import 'hsl.dart';
import 'luminance.dart';

/// One tonal range's color-wheel position (hue/saturation) plus an
/// independent brightness offset — mirrors Lightroom's Color Grading
/// wheels. [saturation] of 0 means "no tint" regardless of [hue]
/// (matching where the wheel's puck sits at dead center).
class GradeRange {
  const GradeRange({this.hue = 0, this.saturation = 0, this.luminance = 0});

  final double hue; // degrees, 0..360
  final double saturation; // 0..100 — wheel puck distance from center
  final double luminance; // -100..100

  bool get isIdentity => saturation == 0 && luminance == 0;

  GradeRange copyWith({double? hue, double? saturation, double? luminance}) =>
      GradeRange(
        hue: hue ?? this.hue,
        saturation: saturation ?? this.saturation,
        luminance: luminance ?? this.luminance,
      );
}

/// The four tonal ranges Lightroom's Color Grading panel exposes —
/// Shadows/Midtones/Highlights plus a Global wheel that tints uniformly
/// across the whole tonal range. Blending/balance controls between ranges
/// aren't modeled.
class ColorGradingValues {
  const ColorGradingValues({
    this.shadows = const GradeRange(),
    this.midtones = const GradeRange(),
    this.highlights = const GradeRange(),
    this.global = const GradeRange(),
  });

  /// Builds grading values from the editor's flat `{sliderName: value}`
  /// map — each range's three values are keyed "Grade" + range name +
  /// "Hue/Saturation/Luminance" (e.g. `'GradeShadowsHue'`).
  factory ColorGradingValues.fromValues(Map<String, double> values) {
    GradeRange range(String name) => GradeRange(
      hue: values['Grade${name}Hue'] ?? 0,
      saturation: values['Grade${name}Saturation'] ?? 0,
      luminance: values['Grade${name}Luminance'] ?? 0,
    );
    return ColorGradingValues(
      shadows: range('Shadows'),
      midtones: range('Midtones'),
      highlights: range('Highlights'),
      global: range('Global'),
    );
  }

  final GradeRange shadows;
  final GradeRange midtones;
  final GradeRange highlights;
  final GradeRange global;

  bool get isIdentity =>
      shadows.isIdentity &&
      midtones.isIdentity &&
      highlights.isIdentity &&
      global.isIdentity;
}

/// How strongly a fully-saturated wheel color tints the image — tuned so
/// the effect is visible without immediately overwhelming the photo's own
/// color, similar in scale to the app's other color adjustments. Public
/// so the GPU render path (`lib/render/gpu/render_gpu.dart`) can reuse
/// [gradeTintOffset]'s exact math for its per-range uniforms instead of
/// duplicating it and risking drift.
const gradeTintStrength = 0.6;

/// A signed RGB offset around neutral gray representing [range]'s wheel
/// position — zero when saturation is 0, matching every other
/// adjustment's no-op rule.
List<double> gradeTintOffset(GradeRange range) {
  if (range.saturation == 0) {
    return const [0.0, 0.0, 0.0];
  }
  final rgb = hslToRgb(
    range.hue,
    (range.saturation / 100).clamp(0.0, 1.0),
    0.5,
  );
  return [
    (rgb[0] * 255 - 127.5) * gradeTintStrength,
    (rgb[1] * 255 - 127.5) * gradeTintStrength,
    (rgb[2] * 255 - 127.5) * gradeTintStrength,
  ];
}

/// Applies Lightroom-style Color Grading (per-range color tint + a
/// luminance offset for shadows, midtones and highlights) to packed RGB
/// [img] in place — a no-op when every range is at its default.
///
/// Designed to run via `compute()`: pure function over simple,
/// isolate-transferable data (same as the rest of render.dart).
void applyColorGrading(Float32List img, ColorGradingValues grading) {
  if (grading.isIdentity) {
    return;
  }
  final shadowTint = gradeTintOffset(grading.shadows);
  final midTint = gradeTintOffset(grading.midtones);
  final highlightTint = gradeTintOffset(grading.highlights);
  final globalTint = gradeTintOffset(grading.global);
  final globalLumOffset = grading.global.luminance / 100.0 * 80.0;

  for (var i = 0; i < img.length; i += 3) {
    final r = img[i];
    final g = img[i + 1];
    final b = img[i + 2];
    final lum = (luminanceRgb(r, g, b) / 255.0).clamp(0.0, 1.0);

    // Partition of unity over [0,1] — shadows peak at lum=0, highlights at
    // lum=1, midtones in between, each tapering to 0 by the next range.
    final shadowW = (1.0 - lum * 2.0).clamp(0.0, 1.0);
    final highlightW = (lum * 2.0 - 1.0).clamp(0.0, 1.0);
    final midW = (1.0 - shadowW - highlightW).clamp(0.0, 1.0);

    var dr = 0.0, dg = 0.0, db = 0.0;
    if (shadowW > 0) {
      dr += shadowTint[0] * shadowW;
      dg += shadowTint[1] * shadowW;
      db += shadowTint[2] * shadowW;
      final lumOffset = shadowW * grading.shadows.luminance / 100.0 * 80.0;
      dr += lumOffset;
      dg += lumOffset;
      db += lumOffset;
    }
    if (midW > 0) {
      dr += midTint[0] * midW;
      dg += midTint[1] * midW;
      db += midTint[2] * midW;
      final lumOffset = midW * grading.midtones.luminance / 100.0 * 80.0;
      dr += lumOffset;
      dg += lumOffset;
      db += lumOffset;
    }
    if (highlightW > 0) {
      dr += highlightTint[0] * highlightW;
      dg += highlightTint[1] * highlightW;
      db += highlightTint[2] * highlightW;
      final lumOffset =
          highlightW * grading.highlights.luminance / 100.0 * 80.0;
      dr += lumOffset;
      dg += lumOffset;
      db += lumOffset;
    }
    // Global applies at full strength everywhere, independent of the
    // shadow/midtone/highlight partition above.
    dr += globalTint[0] + globalLumOffset;
    dg += globalTint[1] + globalLumOffset;
    db += globalTint[2] + globalLumOffset;

    img[i] = r + dr;
    img[i + 1] = g + dg;
    img[i + 2] = b + db;
  }
}
