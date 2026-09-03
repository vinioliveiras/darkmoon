// Hand-authored (not fitted) per-hue "darkmoon Color" profiles — creative
// grades built directly as smooth functions of hue, the same wraparound-
// Gaussian shape `lib/render/color_mixer.dart`'s `_rawHslInfluence` and
// `tool/build_color_profile.dart`'s `smoothHue` already use, rather than
// picking 24 numbers by hand per profile.
//
// Every profile keeps the tone curve at identity (see color_profile.dart's
// ColorProfile) — same v1 scope as the fitted Vivid profile, and the same
// reason: a tone curve is what caused every real incident in this
// feature's history (project_darkmoon_color_profile.md). These are
// per-hue hue-rotation/saturation/luminance grades only.
//
// Usage: dart run tool/author_color_profiles.dart
// Writes straight into assets/color_profiles/.

import 'dart:io';
import 'dart:math' as math;

import 'package:darkmoon/render/color_profile.dart';

/// Wraparound angular distance in degrees, 0..180.
double _hueDist(double a, double b) {
  var d = (a - b).abs() % 360.0;
  if (d > 180.0) d = 360.0 - d;
  return d;
}

/// A bump centered on [hue] with [width]° half-width, [amount] at the
/// centre, falling off smoothly (same shape as color_mixer.dart's own
/// per-band influence) and essentially zero past ~2 widths away.
double _bump(double atHue, double centerHue, double width, double amount) {
  final d = _hueDist(atHue, centerHue);
  return amount * math.exp(-1.35 * (d / width) * (d / width));
}

/// Sums several bumps at one sample hue.
///
/// Deliberate design note (2026-09-01, learned from the first authoring
/// pass): plain addition is fine for a *few sparse* bumps (2-4, covering
/// only part of the wheel — Golden Hour/Teal & Orange below), but blows up
/// for a profile meant to touch *every* hue near-uniformly (Pastel/Noir) —
/// enough overlapping wide bumps to cover 360° stack in their overlap
/// zones and compound well past any single bump's own amount, which is
/// exactly what made the first Pastel attempt read as near-monochrome
/// instead of softly desaturated. Uniform, non-selective adjustments use
/// [_flat] instead, not a wall of overlapping bumps.
double _sum(
  double atHue,
  List<(double center, double width, double amount)> bumps,
) {
  var total = 0.0;
  for (final (center, width, amount) in bumps) {
    total += _bump(atHue, center, width, amount);
  }
  return total;
}

/// A hue-independent contribution, same at every bin — for profiles (or
/// parts of one) that are meant to touch every colour equally rather than
/// target specific hues. See [_sum]'s doc for why this exists separately.
double _flat(double amount) => amount;

// ignore: unused_element — kept for the next hand-authored profile, see main().
ColorProfile _build(
  String name, {
  required List<(double, double, double)> hue,
  required List<(double, double, double)> sat,
  required List<(double, double, double)> lum,
  double satFlat = 0,
  double lumFlat = 0,
}) {
  final hueShift = <double>[];
  final satMul = <double>[];
  final lumMul = <double>[];
  for (var b = 0; b < colorProfileBins; b++) {
    final centre = b * (360.0 / colorProfileBins);
    hueShift.add(_sum(centre, hue));
    satMul.add(1.0 + _flat(satFlat) + _sum(centre, sat));
    lumMul.add(1.0 + _flat(lumFlat) + _sum(centre, lum));
  }
  return ColorProfile(
    tone: identityColorProfile.tone,
    hueShift: hueShift,
    satMul: satMul,
    lumMul: lumMul,
    name: name,
  );
}

void main() {
  // Every hand-authored profile built with this tool ("Golden Hour"/"Teal
  // & Orange" shipped 2026-09-01, removed 2026-09-02; "Pastel"/"Noir"
  // shipped 2026-09-01, removed 2026-09-03, explicit user request) has
  // since been removed — only the fitted Vivid profile remains active.
  // See git history for any of their _build(...) calls if reviving one;
  // the helpers above (_bump/_sum/_flat/_build) are unchanged and ready
  // to reuse.
  stdout.writeln('No hand-authored profiles defined — nothing to write.');
}
