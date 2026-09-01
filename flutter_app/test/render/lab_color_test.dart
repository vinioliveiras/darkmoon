import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/lab_color.dart';

void main() {
  test('rgbToLab/labToRgb round-trips representative colors', () {
    const colors = [
      (0.0, 0.0, 0.0), // black
      (1.0, 1.0, 1.0), // white
      (0.5, 0.5, 0.5), // mid gray
      (1.0, 0.0, 0.0), // red
      (0.0, 1.0, 0.0), // green
      (0.0, 0.0, 1.0), // blue
      (0.2, 0.6, 0.9), // an arbitrary sky-blue-ish color
    ];
    for (final (r, g, b) in colors) {
      final lab = rgbToLab(r, g, b);
      final rgb = labToRgb(lab.l, lab.a, lab.b);
      expect(rgb.r, closeTo(r, 1e-3));
      expect(rgb.g, closeTo(g, 1e-3));
      expect(rgb.b, closeTo(b, 1e-3));
    }
  });

  test('a neutral gray has a == 0 and b == 0 (no color cast)', () {
    // Tolerance is generous, not exact-math: srgbToLinear/linearToSrgb
    // are LUT-interpolated (see color_space_test.dart's own doc comment
    // on why), so a little floating-point drift is expected through this
    // 3x-chained matrix/cube-root pipeline — 0.01 out of Lab's roughly
    // ±127 a/b range is still nowhere near visible.
    for (final gray in [0.1, 0.5, 0.9]) {
      final lab = rgbToLab(gray, gray, gray);
      expect(lab.a, closeTo(0.0, 1e-2));
      expect(lab.b, closeTo(0.0, 1e-2));
    }
  });

  test('L is 0 for black and 100 for white', () {
    expect(rgbToLab(0.0, 0.0, 0.0).l, closeTo(0.0, 1e-3));
    expect(rgbToLab(1.0, 1.0, 1.0).l, closeTo(100.0, 1e-3));
  });
}
