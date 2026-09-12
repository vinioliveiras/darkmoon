// Replace color (2026-09-13, PENDING item 46 — Photomator's tool): pick a
// colour in the photo and move everything near it in hue, saturation
// and luminance, with a range and a softness around the picked colour.
// The last global stage on both paths, after Film, so the colour the
// user picks off the screen is exactly the colour the stage compares
// against (render.dart's applyGlobalPointOps; replace_color.frag on the
// GPU — keep the two identical).
//
// The reach is the colour-range mask's: an RGB distance to the picked
// colour, full weight inside `tolerance`, a smooth ramp over `feather`,
// nothing beyond (see mask.dart's _computeColorRangeAlpha).

import 'dart:math' as math;
import 'dart:typed_data';

import 'hsl.dart';

/// RGB distance (0..255 per channel) that 100 on the Range slider reaches.
const replaceColorMaxCoreDistance = 300.0;

/// RGB distance 100 on the Softness slider adds past the range.
const replaceColorMaxFeatherDistance = 150.0;

/// The slider keys as the editor stores them (see `editor/definitions.dart`).
const replaceColorPickedKey = 'ReplaceColorPicked';
const replaceColorRKey = 'ReplaceColorR';
const replaceColorGKey = 'ReplaceColorG';
const replaceColorBKey = 'ReplaceColorB';
const replaceColorToleranceKey = 'ReplaceColorTolerance';
const replaceColorFeatherKey = 'ReplaceColorFeather';
const replaceColorHueKey = 'ReplaceColorHue';
const replaceColorSaturationKey = 'ReplaceColorSaturation';
const replaceColorLuminanceKey = 'ReplaceColorLuminance';
const replaceColorAmountKey = 'ReplaceColorAmount';

class ReplaceColorParams {
  const ReplaceColorParams({
    this.picked = false,
    this.r = 128,
    this.g = 128,
    this.b = 128,
    this.tolerance = 30,
    this.feather = 25,
    this.hue = 0,
    this.saturation = 0,
    this.luminance = 0,
    this.amount = 50,
  });

  factory ReplaceColorParams.fromValues(Map<String, double> values) =>
      ReplaceColorParams(
        picked: (values[replaceColorPickedKey] ?? 0) > 0,
        r: values[replaceColorRKey] ?? 128,
        g: values[replaceColorGKey] ?? 128,
        b: values[replaceColorBKey] ?? 128,
        tolerance: values[replaceColorToleranceKey] ?? 30,
        feather: values[replaceColorFeatherKey] ?? 25,
        hue: values[replaceColorHueKey] ?? 0,
        saturation: values[replaceColorSaturationKey] ?? 0,
        luminance: values[replaceColorLuminanceKey] ?? 0,
        amount: values[replaceColorAmountKey] ?? 50,
      );

  /// Nothing runs until a colour has been picked off the photo.
  final bool picked;

  /// The picked colour, 0..255 per channel.
  final double r;
  final double g;
  final double b;

  /// 0..100: how far from the picked colour still counts fully.
  final double tolerance;

  /// 0..100: the ramp past [tolerance].
  final double feather;

  /// Degrees, -180..180.
  final double hue;

  /// -100..100, a multiplier on the pixel's saturation.
  final double saturation;

  /// -100..100, a multiplier on the pixel's value.
  final double luminance;

  /// 0..100 blend of the result over the untouched pixel.
  final double amount;

  bool get isIdentity =>
      !picked || amount <= 0 || (hue == 0 && saturation == 0 && luminance == 0);

  /// The RGB distance inside which a pixel takes the full change.
  double get coreDistance =>
      tolerance.clamp(0.0, 100.0) / 100.0 * replaceColorMaxCoreDistance;

  /// The distance the ramp spans past [coreDistance].
  double get featherDistance =>
      feather.clamp(0.0, 100.0) / 100.0 * replaceColorMaxFeatherDistance;
}

/// How much of the change a pixel [distance] away from the picked colour
/// takes: 1 inside the range, a smoothstep ramp across the softness, 0
/// beyond — the colour-range mask's own feather curve.
double replaceColorWeight(double distance, double core, double featherSpan) {
  if (distance <= core) return 1.0;
  if (featherSpan <= 0 || distance >= core + featherSpan) return 0.0;
  final t = ((distance - core) / featherSpan).clamp(0.0, 1.0);
  return 1.0 - t * t * (3.0 - 2.0 * t);
}

/// Applies [p] to the packed RGB 0..255 [buffer] in place.
void applyReplaceColor(Float32List buffer, ReplaceColorParams p) {
  if (p.isIdentity) return;
  final core = p.coreDistance;
  final featherSpan = p.featherDistance;
  final amount = p.amount.clamp(0.0, 100.0) / 100.0;
  final satMul = 1.0 + p.saturation.clamp(-100.0, 100.0) / 100.0;
  final lumMul = 1.0 + p.luminance.clamp(-100.0, 100.0) / 100.0;
  final hueShift = p.hue;
  for (var i = 0; i < buffer.length; i += 3) {
    final r = buffer[i], g = buffer[i + 1], b = buffer[i + 2];
    final dr = r - p.r, dg = g - p.g, db = b - p.b;
    final w =
        replaceColorWeight(
          math.sqrt(dr * dr + dg * dg + db * db),
          core,
          featherSpan,
        ) *
        amount;
    if (w <= 0) continue;
    final (h, s, v) = rgbToHsv(r / 255.0, g / 255.0, b / 255.0);
    var nh = (h + hueShift) % 360.0;
    if (nh < 0) nh += 360.0;
    final (nr, ng, nb) = hsvToRgb(
      nh,
      (s * satMul).clamp(0.0, 1.0),
      (v * lumMul).clamp(0.0, 1.0),
    );
    buffer[i] = r + (nr * 255.0 - r) * w;
    buffer[i + 1] = g + (ng * 255.0 - g) * w;
    buffer[i + 2] = b + (nb * 255.0 - b) * w;
  }
}
