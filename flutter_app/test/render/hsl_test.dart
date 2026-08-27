import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/hsl.dart';

void main() {
  group('rgbToHsv / hsvToRgb', () {
    test('round-trips a handful of colors', () {
      const colors = [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.2, 0.6, 0.9],
        [0.5, 0.5, 0.5],
        [1.0, 1.0, 1.0],
        [0.0, 0.0, 0.0],
      ];
      for (final c in colors) {
        final hsv = rgbToHsv(c[0], c[1], c[2]);
        final rgb = hsvToRgb(hsv[0], hsv[1], hsv[2]);
        expect(rgb[0], closeTo(c[0], 1e-9), reason: 'r for $c');
        expect(rgb[1], closeTo(c[1], 1e-9), reason: 'g for $c');
        expect(rgb[2], closeTo(c[2], 1e-9), reason: 'b for $c');
      }
    });

    test('value is the max channel, unlike HSL lightness', () {
      // A saturated primary's HSV value is 1.0 (the max channel), while
      // its HSL lightness would be 0.5 ((max+min)/2) — this is the whole
      // reason color_mixer.dart moved from rgbToHsl to rgbToHsv.
      final hsv = rgbToHsv(1.0, 0.0, 0.0);
      expect(hsv[2], closeTo(1.0, 1e-9));
    });

    test('pure red is hue 0', () {
      final hsv = rgbToHsv(1.0, 0.0, 0.0);
      expect(hsv[0], closeTo(0.0, 1e-9));
      expect(hsv[1], closeTo(1.0, 1e-9));
    });
  });
}
