import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/mask.dart';

void main() {
  group('MaskLayer.opacity', () {
    test('defaults to 100 (full strength, no change in behavior)', () {
      const mask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.radialGradient,
      );
      expect(mask.opacity, 100);
    });

    test('scales the computed alpha uniformly', () {
      const fullMask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.radialGradient,
        radial: RadialGradientGeometry(
          centerX: 0.5,
          centerY: 0.5,
          radius: 10,
          feather: 0,
        ),
      );
      final fullAlpha = computeMaskAlpha(fullMask, 4, 4);

      final halfMask = fullMask.copyWith(opacity: 50);
      final halfAlpha = computeMaskAlpha(halfMask, 4, 4);

      for (var i = 0; i < fullAlpha.length; i++) {
        expect(halfAlpha[i], closeTo(fullAlpha[i] * 0.5, 1e-9));
      }
    });

    test('0 opacity zeroes out the alpha entirely', () {
      const mask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.radialGradient,
        radial: RadialGradientGeometry(
          centerX: 0.5,
          centerY: 0.5,
          radius: 10,
          feather: 0,
        ),
        opacity: 0,
      );
      final alpha = computeMaskAlpha(mask, 4, 4);
      for (final v in alpha) {
        expect(v, 0.0);
      }
    });

    test('applies after inversion', () {
      const inverted = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.radialGradient,
        radial: RadialGradientGeometry(
          centerX: 0.5,
          centerY: 0.5,
          radius: 0,
          feather: 0,
        ),
        inverted: true,
        opacity: 50,
      );
      final alpha = computeMaskAlpha(inverted, 4, 4);
      // A near-zero-radius circle covers essentially nothing, so inverted
      // covers everything at full alpha (1.0) before opacity — except
      // possibly the exact center pixel, which the tiny nonzero radius
      // clamp may still catch — 50% opacity should halve every other
      // pixel's alpha.
      final farFromCenter = [
        for (var y = 0; y < 4; y++)
          for (var x = 0; x < 4; x++)
            if ((x - 1.5).abs() > 0.6 || (y - 1.5).abs() > 0.6) y * 4 + x,
      ];
      for (final i in farFromCenter) {
        expect(alpha[i], closeTo(0.5, 1e-6));
      }
    });
  });
}
