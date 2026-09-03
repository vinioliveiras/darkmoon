import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/mask.dart';

/// Pins the radial mask's ellipse + rotation geometry: both semi-axes are
/// fractions of the image *width* (so equal values are a true circle in
/// pixel space, whatever the aspect ratio), and [RadialGradientGeometry.angle]
/// spins the shape clockwise on screen.
void main() {
  // 200x100 landscape image, mask centered: cx = 100, cy = 50 px.
  const width = 200;
  const height = 100;

  MaskLayer radial(RadialGradientGeometry g) => MaskLayer(
    id: 'm',
    name: 'Mask',
    type: MaskType.radialGradient,
    radial: g,
  );

  double alphaAt(Float32List alpha, int x, int y) => alpha[y * width + x];

  group('radial mask geometry', () {
    test('radiusY null renders a true pixel-space circle', () {
      // radius 0.25 of width = 50 px in BOTH directions, despite the 2:1
      // aspect ratio. feather 0 = hard edge.
      final alpha = computeMaskAlpha(
        radial(const RadialGradientGeometry(feather: 0)),
        width,
        height,
      );
      expect(alphaAt(alpha, 140, 50), 1.0); // 40 px right: inside
      expect(alphaAt(alpha, 100, 95), 1.0); // 45 px down: inside
      expect(alphaAt(alpha, 155, 50), 0.0); // 55 px right: outside
      expect(alphaAt(alpha, 155, 95), 0.0); // diagonal ~67 px: outside
    });

    test('radiusY stretches only the Y axis', () {
      // 50 px wide, 20 px tall.
      final alpha = computeMaskAlpha(
        radial(const RadialGradientGeometry(radiusY: 0.1, feather: 0)),
        width,
        height,
      );
      expect(alphaAt(alpha, 140, 50), 1.0); // 40 px right: inside
      expect(alphaAt(alpha, 100, 65), 1.0); // 15 px down: inside
      expect(alphaAt(alpha, 100, 90), 0.0); // 40 px down: outside
    });

    test('angle rotates the ellipse', () {
      // Same 50x20 ellipse spun 90 degrees: the long axis now runs
      // vertically, so the horizontal probe that was inside falls out
      // and the vertical one that was outside falls in.
      final alpha = computeMaskAlpha(
        radial(
          RadialGradientGeometry(radiusY: 0.1, angle: math.pi / 2, feather: 0),
        ),
        width,
        height,
      );
      expect(alphaAt(alpha, 140, 50), 0.0); // 40 px right: now outside
      expect(alphaAt(alpha, 100, 90), 1.0); // 40 px down: now inside
    });

    test('feather fades over the outer fraction of the shape', () {
      // feather 0.5: full strength inside half the radius (25 px),
      // linear falloff from there to the 50 px rim.
      final alpha = computeMaskAlpha(
        radial(const RadialGradientGeometry(feather: 0.5)),
        width,
        height,
      );
      expect(alphaAt(alpha, 110, 50), 1.0); // 10 px: inner region
      expect(alphaAt(alpha, 155, 50), 0.0); // 55 px: past the rim
      // 37.5 px out = normalized t 0.75, halfway through the falloff.
      final mid = alphaAt(alpha, 138, 50);
      expect(mid, greaterThan(0.4));
      expect(mid, lessThan(0.6));
    });
  });
}
