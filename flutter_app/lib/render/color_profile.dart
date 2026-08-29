import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'color_space.dart';
import 'hsl.dart';

/// Number of hue bins the profile table carries — one every 15°.
const int colorProfileBins = 24;
const double _binWidth = 360.0 / colorProfileBins;

/// darkmoon's stand-in for the Adobe Color profile's HueSatMap: a fitted
/// per-hue correction that nudges every photo's colours toward how
/// Lightroom renders the same RAW, closing the gap that darkmoon's plain
/// LibRaw demosaic + colour matrix leaves (greens/oranges/blues land at a
/// visibly different hue/brightness — see the Filmatic Fuji comparison in
/// PENDING.md item 14).
///
/// The table is [colorProfileBins] bins around the hue circle, each with a
/// hue rotation (degrees), a saturation multiplier and a luminance
/// multiplier. Built by `tool/build_color_profile.dart` from pairs of
/// (darkmoon-neutral render, Lightroom Adobe-Color-neutral export); applied
/// by [applyColorProfile] right after the base contrast curve, before any
/// user adjustment — the same spot Lightroom runs the profile.
class ColorProfile {
  const ColorProfile({
    required this.hueShift,
    required this.satMul,
    required this.lumMul,
    this.name = '',
  });

  /// Per-bin hue rotation in degrees (bin `i` centres on `i * 15°`).
  final List<double> hueShift;

  /// Per-bin saturation multiplier (1.0 = unchanged).
  final List<double> satMul;

  /// Per-bin luminance multiplier (1.0 = unchanged).
  final List<double> lumMul;

  final String name;

  bool get isIdentity {
    for (var i = 0; i < colorProfileBins; i++) {
      if (hueShift[i] != 0 || satMul[i] != 1.0 || lumMul[i] != 1.0) {
        return false;
      }
    }
    return true;
  }

  factory ColorProfile.fromJson(Map<String, dynamic> json) {
    List<double> col(String key, double fallback) {
      final raw = json[key];
      if (raw is! List || raw.length != colorProfileBins) {
        return List<double>.filled(colorProfileBins, fallback);
      }
      return [for (final v in raw) (v as num).toDouble()];
    }

    return ColorProfile(
      hueShift: col('hueShift', 0),
      satMul: col('satMul', 1),
      lumMul: col('lumMul', 1),
      name: json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'bins': colorProfileBins,
    'hueShift': hueShift,
    'satMul': satMul,
    'lumMul': lumMul,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static ColorProfile decode(String source) =>
      ColorProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

final ColorProfile identityColorProfile = ColorProfile(
  hueShift: List<double>.filled(colorProfileBins, 0),
  satMul: List<double>.filled(colorProfileBins, 1),
  lumMul: List<double>.filled(colorProfileBins, 1),
);

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

double _linearLuma(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

/// Applies [profile] to packed RGB [img] (0..255-valued [Float32List], the
/// pipeline's working buffer) in place. [strength] 0..1 blends the whole
/// correction toward identity (backs the "darkmoon Color" amount slider).
///
/// Same structure as `color_mixer.dart`'s `applyColorMixer`: works in
/// scene-linear HSV, rotates hue / scales saturation by a hue-interpolated
/// amount gated by how saturated the source already is (a gray pixel's hue
/// is noise), then restores luminance to the profile's target via a
/// proportional rescale.
void applyColorProfile(Float32List img, ColorProfile profile, double strength) {
  if (strength <= 0 || profile.isIdentity) {
    return;
  }
  final s = strength.clamp(0.0, 1.0);

  for (var i = 0; i < img.length; i += 3) {
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    if ((r - g).abs() < 0.001 && (g - b).abs() < 0.001) {
      continue; // neutral — nothing to rotate
    }

    final hsv = rgbToHsv(r, g, b);
    final hue = hsv[0];
    final sat = hsv[1];
    final val = hsv[2];
    final originalLuma = _linearLuma(r, g, b);

    final mask = _smoothstep(0.04, 0.18, sat);
    if (mask < 0.001) {
      continue;
    }

    // Hue -> bin, linear interpolation between the two nearest bin centres.
    final f = hue / _binWidth;
    final i0 = f.floor() % colorProfileBins;
    final i1 = (i0 + 1) % colorProfileBins;
    final frac = f - f.floor();
    final hueShiftDeg =
        (profile.hueShift[i0] * (1 - frac) + profile.hueShift[i1] * frac) *
        s *
        mask;
    final satMul =
        (1.0 +
        (profile.satMul[i0] * (1 - frac) + profile.satMul[i1] * frac - 1.0) *
            s *
            mask);
    final lumMul =
        (1.0 +
        (profile.lumMul[i0] * (1 - frac) + profile.lumMul[i1] * frac - 1.0) *
            s *
            mask);

    var newHue = (hue + hueShiftDeg) % 360.0;
    if (newHue < 0) {
      newHue += 360.0;
    }
    final newSat = (sat * satMul).clamp(0.0, 1.0);
    final shifted = hsvToRgb(newHue, newSat, val);
    final shiftedLuma = _linearLuma(shifted[0], shifted[1], shifted[2]);
    final targetLuma = originalLuma * lumMul;

    final double fr;
    final double fg;
    final double fb;
    if (shiftedLuma < 0.0001) {
      fr = fg = fb = math.max(0.0, targetLuma);
    } else {
      final rescale = targetLuma / shiftedLuma;
      fr = shifted[0] * rescale;
      fg = shifted[1] * rescale;
      fb = shifted[2] * rescale;
    }
    img[i] = linearToSrgb(fr) * 255.0;
    img[i + 1] = linearToSrgb(fg) * 255.0;
    img[i + 2] = linearToSrgb(fb) * 255.0;
  }
}
