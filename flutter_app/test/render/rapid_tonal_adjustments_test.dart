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

  // The next three cases lock in RapidRAW's apply_creative_color: both
  // Saturation and Vibrance mix toward luminance in *scene-linear* light
  // (not the gamma-encoded byte values), and Saturation runs before
  // Vibrance so Vibrance's own saturation/hue masks read the
  // already-saturated color. Expected values below were computed from the
  // same sRGB<->linear conversion and mix formula in a reference Python
  // script, independent of render.dart's implementation.

  test('saturation mixes toward luminance in linear light', () {
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

    expect(saturated[0], closeTo(235, 1));
    expect(saturated[1], closeTo(0, 1));
    expect(saturated[2], closeTo(0, 1));
    expect(desaturated[0], closeTo(166, 1));
    expect(desaturated[1], closeTo(86, 1));
    expect(desaturated[2], closeTo(86, 1));
  });

  test('vibrance mixes toward luminance in linear light', () {
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

    expect(boosted[0], closeTo(81, 1));
    expect(boosted[1], closeTo(153, 1));
    expect(boosted[2], closeTo(207, 1));
    expect(reduced[0], closeTo(124, 1));
    expect(reduced[1], closeTo(150, 1));
    expect(reduced[2], closeTo(176, 1));
  });

  test('saturation runs before vibrance, matching apply_creative_color', () {
    final result = renderRgb(
      1,
      1,
      Uint8List.fromList([120, 150, 180]),
      const RenderParams(baseContrast: 0, saturation: 30, vibrance: 40),
    );

    // Applying the two steps in the opposite order (vibrance's masks
    // reading the *original* color) would instead land near (61, 154, 215)
    // — well outside this tolerance.
    expect(result[0], closeTo(87, 1));
    expect(result[1], closeTo(153, 1));
    expect(result[2], closeTo(204, 1));
  });
}
