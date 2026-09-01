import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

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
    final saturated = renderRgb(
      1,
      1,
      Uint8List.fromList([204, 51, 51]),
      const RenderParams(baseContrast: 0, saturation: 50),
    );
    final desaturated = renderRgb(
      1,
      1,
      Uint8List.fromList([204, 51, 51]),
      const RenderParams(baseContrast: 0, saturation: -50),
    );

    // (204, 51, 51) — sat=0.75, factor = 1 + 0.5*calSaturationStrength
    // (0.35, 2026-09-01) at +50%, so the max channel (204, this pixel's
    // HSV "value") is exactly preserved; the *min* channel is what
    // saturating moves.
    expect(saturated[0], closeTo(204, 1));
    expect(saturated[1], closeTo(24, 1));
    expect(saturated[2], closeTo(24, 1));
    expect(desaturated[0], closeTo(204, 1));
    expect(desaturated[1], closeTo(78, 1));
    expect(desaturated[2], closeTo(78, 1));
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

    // The max channel (180, blue) is this pixel's HSV "value" — held
    // exactly fixed in both directions by construction. Boosted values
    // reflect calVibranceStrength=0.5/calVibranceSkinDampen=0.2
    // (2026-09-01) — the negative branch doesn't depend on either
    // constant, so it's unchanged.
    expect(boosted[0], closeTo(105, 1));
    expect(boosted[1], closeTo(143, 1));
    expect(boosted[2], closeTo(180, 1));
    expect(reduced[0], closeTo(146, 1));
    expect(reduced[1], closeTo(163, 1));
    expect(reduced[2], closeTo(180, 1));
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
    // stage went first is still measurable), just far more subtly, which
    // this narrower expectation locks in. Values reflect
    // calSaturationStrength=0.35/calVibranceStrength=0.5/
    // calVibranceSkinDampen=0.2 (2026-09-01).
    expect(result[0], closeTo(100, 1));
    expect(result[1], closeTo(140, 1));
    expect(result[2], closeTo(180, 1));
  });
}
