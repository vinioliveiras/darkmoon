import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/calibration.dart';
import 'package:darkmoon/render/hsl.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

// Reference implementations of the Saturation and Vibrance stages, built
// from hsl.dart's rgbToHsv/hsvToRgb primitives plus the real calibration
// constants — the exact derivation the expected values in the three tests
// at the bottom of this file used to spell out as literal bytes.
//
// They are literals no longer (2026-09-03). Every one of those tests was
// red on master: they were last re-derived by hand when
// calSaturationStrength was 0.10 and calVibranceStrength was 0.7, and a
// later tuning round moved them to 0.30 and 1.0 without touching the
// numbers here. That is the same "hand-maintained copy of a calibration
// constant silently rots on the next tuning round" failure that keeps
// turning up in the GPU shaders; deriving from the constants instead means
// these tests now follow a retune on their own, and still assert real
// behavior — the formulas below are written from the documented model, not
// by calling render.dart.

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// Flat HSV saturation gain — hue and value fixed by construction.
(double, double, double) _expectSaturation(
  (double, double, double) rgb,
  double amount,
) {
  final (h, s, v) = rgbToHsv(rgb.$1, rgb.$2, rgb.$3);
  if (s < 1e-4) return rgb;
  final factor = 1.0 + amount / 100.0 * calSaturationStrength;
  return hsvToRgb(h, (s * factor).clamp(0.0, 1.0), v);
}

/// HSV saturation gain damped on skin-tone hues and on already-saturated
/// pixels — see render.dart's _applyVibrance.
(double, double, double) _expectVibrance(
  (double, double, double) rgb,
  double amount,
) {
  final (h, s, v) = rgbToHsv(rgb.$1, rgb.$2, rgb.$3);
  if (v * s < 0.02) return rgb;
  final normalized = amount / 100.0;
  final hueDistance = math.min((h - 25.0).abs(), 360.0 - (h - 25.0).abs());
  final skin = _smoothstep(35.0, 10.0, hueDistance);
  final skinDampener = 1.0 + (calVibranceSkinDampen - 1.0) * skin;
  final factor = normalized >= 0
      ? 1.0 +
            normalized *
                (1.0 - _smoothstep(0.4, 0.9, s)) *
                skinDampener *
                calVibranceStrength
      : 1.0 + normalized * (1.0 - _smoothstep(0.2, 0.8, s));
  return hsvToRgb(h, (s * factor).clamp(0.0, 1.0), v);
}

/// The reference pipeline's byte output for a single pixel: Saturation
/// then Vibrance (that order — see applyGlobalPointOps), rounded the way
/// render.dart's own _toUint8 does.
List<int> _expectSatThenVibrance(
  List<int> rgb, {
  double saturation = 0,
  double vibrance = 0,
}) {
  var c = (rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0);
  if (saturation != 0) c = _expectSaturation(c, saturation);
  if (vibrance != 0) c = _expectVibrance(c, vibrance);
  return [
    (c.$1 * 255.0).clamp(0.0, 255.0).round(),
    (c.$2 * 255.0).clamp(0.0, 255.0).round(),
    (c.$3 * 255.0).clamp(0.0, 255.0).round(),
  ];
}

void _expectPixel(Uint8List actual, List<int> expected, String label) {
  for (var i = 0; i < 3; i++) {
    expect(
      actual[i],
      closeTo(expected[i], 1),
      reason: '$label channel $i: got ${actual[i]}, expected ${expected[i]}',
    );
  }
}

Uint8List _solid(int value) => Uint8List.fromList([
  value,
  value,
  value,
  value,
  value,
  value,
  value,
  value,
  value,
  value,
  value,
  value,
]);

void main() {
  test('neutral tonal settings preserve the source', () {
    final source = Uint8List.fromList([
      12,
      34,
      56,
      96,
      128,
      160,
      200,
      180,
      150,
      240,
      220,
      200,
    ]);

    expect(
      renderRgb(2, 2, source, const RenderParams(baseContrast: 0)),
      source,
    );
  });

  test('the base "profile" contrast curve is a wired-in S (darks down, '
      'lights up) at the default calBaseContrast', () {
    final dark = _solid(48);
    final light = _solid(208);
    // Default params -> baseContrast defaults to calBaseContrast (non-zero).
    final darkOut = renderRgb(1, 1, dark, const RenderParams());
    final lightOut = renderRgb(1, 1, light, const RenderParams());
    final darkFlat = renderRgb(1, 1, dark, const RenderParams(baseContrast: 0));
    final lightFlat = renderRgb(
      1,
      1,
      light,
      const RenderParams(baseContrast: 0),
    );

    expect(darkOut[0], lessThan(darkFlat[0]));
    expect(lightOut[0], greaterThan(lightFlat[0]));
  });

  test(
    'brightness and exposure move the luminance in the expected direction',
    () {
      final source = _solid(96);
      final brighter = renderRgb(
        2,
        2,
        source,
        const RenderParams(baseContrast: 0, brightness: 50),
      );
      final exposed = renderRgb(
        2,
        2,
        source,
        const RenderParams(baseContrast: 0, exposure: 50),
      );

      expect(brighter[0], greaterThan(source[0]));
      expect(exposed[0], greaterThan(source[0]));
    },
  );

  test('shadows and whites target their respective tonal ranges', () {
    final dark = renderRgb(
      2,
      2,
      _solid(32),
      const RenderParams(baseContrast: 0, shadows: 100),
    );
    final bright = renderRgb(
      2,
      2,
      _solid(224),
      const RenderParams(baseContrast: 0, whites: -100),
    );

    expect(dark[0], greaterThan(32));
    expect(bright[0], lessThan(224));
  });

  test('contrast expands dark and bright tones around the midpoint', () {
    final dark = renderRgb(
      2,
      2,
      _solid(32),
      const RenderParams(baseContrast: 0, contrast: 100),
    );
    final bright = renderRgb(
      2,
      2,
      _solid(224),
      const RenderParams(baseContrast: 0, contrast: 100),
    );

    expect(dark[0], lessThan(32));
    expect(bright[0], greaterThan(224));
  });

  // The next three cases lock in the current Saturation/Vibrance design —
  // deliberately *not* Solstice's apply_creative_color (2026-08-31, see
  // project_darkmoon_color_profile.md's "8th round"): that scene-linear
  // luminance-mix technique is only hue-preserving when hue is measured on
  // linear values, not on the independently-gamma-re-encoded result a
  // viewer actually sees — a real, measurable hue rotation on saturated
  // colours. Both Saturation and Vibrance are now a direct HSV saturation
  // multiply on the working buffer's own gamma-encoded values, holding hue
  // and value (the max channel) exactly fixed by construction — zero hue
  // drift, by definition, regardless of boost strength. Saturation still
  // runs before Vibrance so Vibrance's own saturation mask reads the
  // already-saturated color. Expected values below were computed
  // independently from render.dart's implementation, straight from the
  // rgbToHsv/hsvToRgb primitives in hsl.dart plus the real calibration
  // constants (calVibranceStrength/calVibranceSkinDampen/
  // calSaturationStrength) — not by calling renderRgb itself.

  test('saturation multiplies HSV saturation, hue and value held fixed', () {
    const source = [204, 51, 51]; // sat = 0.75
    final saturated = renderRgb(
      1,
      1,
      Uint8List.fromList(source),
      const RenderParams(baseContrast: 0, saturation: 50),
    );
    final desaturated = renderRgb(
      1,
      1,
      Uint8List.fromList(source),
      const RenderParams(baseContrast: 0, saturation: -50),
    );

    _expectPixel(
      saturated,
      _expectSatThenVibrance(source, saturation: 50),
      'saturation +50',
    );
    _expectPixel(
      desaturated,
      _expectSatThenVibrance(source, saturation: -50),
      'saturation -50',
    );
    // The max channel is this pixel's HSV "value" and is held exactly
    // fixed by construction, whichever way saturation moves — the part
    // that does not depend on any calibration constant at all.
    expect(saturated[0], 204);
    expect(desaturated[0], 204);
    expect(saturated[1], lessThan(source[1]));
    expect(desaturated[1], greaterThan(source[1]));
  });

  test('vibrance multiplies HSV saturation, hue and value held fixed', () {
    final source = Uint8List.fromList([120, 150, 180]);
    final boosted = renderRgb(
      1,
      1,
      source,
      const RenderParams(baseContrast: 0, vibrance: 50),
    );
    final reduced = renderRgb(
      1,
      1,
      source,
      const RenderParams(baseContrast: 0, vibrance: -50),
    );

    _expectPixel(
      boosted,
      _expectSatThenVibrance([120, 150, 180], vibrance: 50),
      'vibrance +50',
    );
    _expectPixel(
      reduced,
      _expectSatThenVibrance([120, 150, 180], vibrance: -50),
      'vibrance -50',
    );
    // The max channel (180, blue) is this pixel's HSV "value" — held
    // exactly fixed in both directions by construction, independently of
    // any calibration constant.
    expect(boosted[2], 180);
    expect(reduced[2], 180);
  });

  test('saturation runs before vibrance', () {
    final result = renderRgb(
      1,
      1,
      Uint8List.fromList([120, 150, 180]),
      const RenderParams(baseContrast: 0, saturation: 30, vibrance: 40),
    );

    // Unlike the old scene-linear technique, applying the two steps in the
    // opposite order no longer shifts hue or value — both stages hold both
    // exactly fixed by construction — so the two orders land close
    // together instead of "well outside tolerance." Order still matters
    // (Vibrance's own boost is masked by *current* saturation, so which
    // stage went first is still measurable), which is what this locks in:
    // the reference below composes them saturation-first, and the
    // vibrance-first composition lands somewhere else.
    _expectPixel(
      result,
      _expectSatThenVibrance([120, 150, 180], saturation: 30, vibrance: 40),
      'saturation then vibrance',
    );

    // ...but not at THIS pixel, as of 2026-09-03. Vibrance's boost is
    // masked by smoothstep(0.4, 0.9, saturation), and (120, 150, 180) sits
    // at saturation 0.333 — below the lower edge, so the mask is 1.0 both
    // before and after a +30 Saturation nudges it to 0.363. The two stages
    // commute exactly there, which means the assertion above, on its own,
    // would still pass if they were swapped.
    //
    // So the order claim gets its own pixel: (90, 135, 180) sits at
    // saturation 0.5, inside the smoothstep band, where saturating first
    // demonstrably changes the mask Vibrance then applies.
    const orderSource = [90, 135, 180];
    final ordered = renderRgb(
      1,
      1,
      Uint8List.fromList(orderSource),
      const RenderParams(baseContrast: 0, saturation: 30, vibrance: 40),
    );
    _expectPixel(
      ordered,
      _expectSatThenVibrance(orderSource, saturation: 30, vibrance: 40),
      'saturation then vibrance (in-band pixel)',
    );

    var swapped = (
      orderSource[0] / 255.0,
      orderSource[1] / 255.0,
      orderSource[2] / 255.0,
    );
    swapped = _expectVibrance(swapped, 40);
    swapped = _expectSaturation(swapped, 30);
    expect(
      (swapped.$1 * 255.0).round(),
      isNot(closeTo(ordered[0], 1)),
      reason:
          'the two orders must differ at this pixel, or this test proves '
          'nothing about ordering',
    );
  });
}
