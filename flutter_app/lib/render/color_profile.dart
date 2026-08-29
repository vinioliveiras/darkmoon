import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'color_space.dart';
import 'hsl.dart';

/// Number of hue bins the per-hue table carries — one every 15°.
const int colorProfileBins = 24;
const double _binWidth = 360.0 / colorProfileBins;

/// Number of points in the tone curve (input perceptual-luma `i/(N-1)`).
const int colorProfileTonePoints = 33;

/// darkmoon's stand-in for an Adobe camera profile ("Adobe Color"): a
/// fitted **tone curve** (the brightness/contrast/shoulder that Adobe's
/// rendering bakes in over LibRaw's flatter, scene-dependent neutral) plus
/// a fitted **per-hue HueSat correction** (the green/orange/blue drift the
/// Filmatic Fuji comparison exposed — PENDING.md item 14).
///
/// Built by `tool/build_color_profile.dart` from pairs of a RAW rendered
/// neutrally in darkmoon and the same RAW exported from Lightroom with the
/// Adobe Color profile, all sliders zeroed. Applied by [applyColorProfile]
/// right after (in place of, when its tone curve is non-identity) the base
/// contrast curve, before any user adjustment — where Lightroom runs the
/// profile.
class ColorProfile {
  const ColorProfile({
    required this.tone,
    required this.hueShift,
    required this.satMul,
    required this.lumMul,
    this.name = '',
  });

  /// Perceptual-luma -> perceptual-luma curve, [colorProfileTonePoints]
  /// points, `tone[i]` the output for input `i / (N - 1)`. Identity is the
  /// straight ramp.
  final List<double> tone;

  /// Per-bin hue rotation in degrees (bin `i` centres on `i * 15°`).
  final List<double> hueShift;

  /// Per-bin saturation multiplier (1.0 = unchanged).
  final List<double> satMul;

  /// Per-bin residual luminance multiplier on top of the tone curve
  /// (1.0 = unchanged).
  final List<double> lumMul;

  final String name;

  bool get toneIsIdentity {
    for (var i = 0; i < tone.length; i++) {
      if ((tone[i] - i / (tone.length - 1)).abs() > 1e-4) return false;
    }
    return true;
  }

  bool get isIdentity {
    if (!toneIsIdentity) return false;
    for (var i = 0; i < colorProfileBins; i++) {
      if (hueShift[i] != 0 || satMul[i] != 1.0 || lumMul[i] != 1.0) {
        return false;
      }
    }
    return true;
  }

  factory ColorProfile.fromJson(Map<String, dynamic> json) {
    List<double> arr(String key, int len, double Function(int) fallback) {
      final raw = json[key];
      if (raw is! List || raw.length != len) {
        return [for (var i = 0; i < len; i++) fallback(i)];
      }
      return [for (final v in raw) (v as num).toDouble()];
    }

    return ColorProfile(
      tone: arr(
        'tone',
        colorProfileTonePoints,
        (i) => i / (colorProfileTonePoints - 1),
      ),
      hueShift: arr('hueShift', colorProfileBins, (_) => 0),
      satMul: arr('satMul', colorProfileBins, (_) => 1),
      lumMul: arr('lumMul', colorProfileBins, (_) => 1),
      name: json['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'bins': colorProfileBins,
    'tone': tone,
    'hueShift': hueShift,
    'satMul': satMul,
    'lumMul': lumMul,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static ColorProfile decode(String source) =>
      ColorProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);
}

final ColorProfile identityColorProfile = ColorProfile(
  tone: [
    for (var i = 0; i < colorProfileTonePoints; i++)
      i / (colorProfileTonePoints - 1),
  ],
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

double _lerpList(List<double> table, double x) {
  final n = table.length;
  final f = (x.clamp(0.0, 1.0)) * (n - 1);
  final i0 = f.floor().clamp(0, n - 1);
  final i1 = (i0 + 1).clamp(0, n - 1);
  return table[i0] + (table[i1] - table[i0]) * (f - i0);
}

/// Applies [profile] to packed RGB [img] (0..255-valued [Float32List], the
/// pipeline's working buffer) in place. [strength] 0..1 blends the whole
/// correction toward identity (backs the "darkmoon Color" amount slider).
///
/// Per pixel: the tone curve first (a chroma-preserving luminance remap in
/// perceptual space — brightness/contrast/shoulder), then the per-hue
/// HueSat correction (scene-linear HSV, saturation-gated so a grey pixel's
/// noisy hue is left alone, luminance restored to the per-hue target).
void applyColorProfile(Float32List img, ColorProfile profile, double strength) {
  if (strength <= 0 || profile.isIdentity) {
    return;
  }
  final s = strength.clamp(0.0, 1.0);
  final doTone = !profile.toneIsIdentity;

  for (var i = 0; i < img.length; i += 3) {
    var r = srgbToLinear(img[i] / 255.0);
    var g = srgbToLinear(img[i + 1] / 255.0);
    var b = srgbToLinear(img[i + 2] / 255.0);

    // 1. Tone curve — remap luminance, keep chroma.
    if (doTone) {
      final linLuma = math.max(_linearLuma(r, g, b), 1e-6);
      final pIn = perceptualEncode(linLuma);
      final pOut = pIn + (_lerpList(profile.tone, pIn) - pIn) * s;
      final scale = perceptualDecode(pOut.clamp(0.0, 2.0)) / linLuma;
      r *= scale;
      g *= scale;
      b *= scale;
    }

    // 2. Per-hue HueSat correction.
    if ((r - g).abs() >= 0.001 || (g - b).abs() >= 0.001) {
      final (hue, sat, val) = rgbToHsv(r, g, b);
      final mask = _smoothstep(0.04, 0.18, sat);
      if (mask >= 0.001) {
        final originalLuma = _linearLuma(r, g, b);
        final f = hue / _binWidth;
        final i0 = f.floor() % colorProfileBins;
        final i1 = (i0 + 1) % colorProfileBins;
        final frac = f - f.floor();
        double at(List<double> t) => t[i0] * (1 - frac) + t[i1] * frac;

        final hueShiftDeg = at(profile.hueShift) * s * mask;
        final satMul = 1.0 + (at(profile.satMul) - 1.0) * s * mask;
        final lumMul = 1.0 + (at(profile.lumMul) - 1.0) * s * mask;

        var newHue = (hue + hueShiftDeg) % 360.0;
        if (newHue < 0) newHue += 360.0;
        final newSat = (sat * satMul).clamp(0.0, 1.0);
        final (sr, sg, sb) = hsvToRgb(newHue, newSat, val);
        final shiftedLuma = _linearLuma(sr, sg, sb);
        final targetLuma = originalLuma * lumMul;
        if (shiftedLuma < 0.0001) {
          r = g = b = math.max(0.0, targetLuma);
        } else {
          final rescale = targetLuma / shiftedLuma;
          r = sr * rescale;
          g = sg * rescale;
          b = sb * rescale;
        }
      }
    }

    img[i] = linearToSrgb(r) * 255.0;
    img[i + 1] = linearToSrgb(g) * 255.0;
    img[i + 2] = linearToSrgb(b) * 255.0;
  }
}
