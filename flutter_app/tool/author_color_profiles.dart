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
double _sum(double atHue, List<(double center, double width, double amount)> bumps) {
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
  // Hue landmarks (matches color_mixer.dart's own band centres): red 358,
  // orange 25, yellow 60, green 115, aqua 180, blue 225, purple 280,
  // magenta 330.
  const red = 358.0, orange = 25.0, yellow = 60.0;
  const green = 115.0, aqua = 180.0, blue = 225.0, magenta = 330.0;

  // ---- Golden Hour: warm glow EVERYWHERE, blues pulled well back ----
  // Amplitudes re-tuned twice (2026-09-01): the first pass was too strong
  // ("everything drenched in yellow"), the second too gentle to read as
  // distinct from Teal & Orange on a warm-dominant photo. This pass keeps
  // Golden Hour a pure warm push (no cool-zone split like Teal & Orange
  // gets) but commits to it — a real "late-day glow," not a hint of one.
  final goldenHour = _build(
    'Golden Hour',
    hue: [
      (yellow, 25, -8), // yellow leans toward orange
      (blue, 40, 6), // blue nudged toward violet -- cooler-reading
    ],
    sat: [
      (orange, 28, 0.22),
      (yellow, 22, 0.13),
      (red, 25, 0.06), // gentle -- keep skin tones believable
      (blue, 35, -0.15),
      (aqua, 30, -0.10),
    ],
    lum: [
      (orange, 28, 0.07),
      (yellow, 22, 0.04),
      (blue, 35, -0.05),
    ],
  );

  // ---- Teal & Orange: a real two-tone SPLIT, not just "warm" ----
  // The point of this profile (vs. Golden Hour) is contrast BETWEEN warm
  // and cool zones, so the cool side needs to read as clearly as the
  // warm one — pushed noticeably harder than the first two passes, with
  // yellow/green pulled toward neutral so the split doesn't muddy.
  final tealOrange = _build(
    'Teal & Orange',
    hue: [
      (aqua, 35, -22), // aqua/cyan pulled hard toward teal
      (blue, 35, -13),
      (yellow, 20, -7), // tuck yellow toward orange, cleans the split
    ],
    sat: [
      (orange, 28, 0.22),
      (red, 25, 0.08),
      (aqua, 38, 0.26),
      (blue, 32, 0.17),
      (yellow, 20, -0.16),
      (green, 32, -0.14),
    ],
    lum: [
      (orange, 28, 0.04),
      (aqua, 38, -0.05),
      (blue, 32, -0.07),
    ],
  );

  // ---- Pastel: bright and airy -- the light, soft opposite of Noir ----
  // Uniform (satFlat/lumFlat), not per-hue bumps -- "pastel" is a global
  // softening, not a selective grade, and see _sum's doc for why stacking
  // 7 overlapping bumps to fake "uniform" badly overcorrected the first
  // attempt (read as near-monochrome, not softly desaturated). Lift
  // raised well above the desaturation this pass (2026-09-01) so it
  // reads as "bright and soft," not just "muted" -- the clearer opposite
  // of Noir's dark-and-desaturated below.
  final pastel = _build(
    'Pastel',
    hue: [
      (magenta, 60, 2), // barely-there warm-pink drift
    ],
    sat: const [],
    lum: const [],
    satFlat: -0.20,
    lumFlat: 0.10,
  );

  // ---- Noir: dark, cool and heavily desaturated -- Pastel's opposite ----
  // (No true B&W/contrast here by design -- tone stays identity, see this
  // file's header. Reads as "cool, subdued, moody," not monochrome --
  // same uniform-via-flat fix as Pastel, plus a couple of small
  // selective accents layered on top for character. Pushed clearly
  // darker/more desaturated than Pastel is bright/soft, 2026-09-01, so
  // the two read as opposites rather than both landing on "muted.")
  final noir = _build(
    'Noir',
    hue: [
      (red, 45, 5), // reds nudged toward magenta -- cooler skin
      (orange, 35, 6), // oranges nudged toward yellow -- less warmth
      (blue, 45, -5), // blue nudged toward aqua -- steelier
    ],
    sat: const [],
    lum: [
      (aqua, 50, 0.04), // faint moonlit lift in the cool end
      (blue, 45, 0.05),
    ],
    satFlat: -0.42,
    lumFlat: -0.09,
  );

  final outDir = Directory('assets/color_profiles');
  for (final profile in [goldenHour, tealOrange, pastel, noir]) {
    final fileName =
        'darkmoon_${profile.name.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '_')}.json';
    final path = '${outDir.path}/$fileName';
    File(path).writeAsStringSync(profile.encode());
    stdout.writeln('wrote $path');
  }
}
