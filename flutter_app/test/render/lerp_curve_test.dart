import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/tone_curve.dart';

void main() {
  group('lerpCurve', () {
    const base = [CurvePoint(0, 0), CurvePoint(0.5, 0.4), CurvePoint(1, 1)];
    const target = [CurvePoint(0, 0), CurvePoint(0.5, 0.8), CurvePoint(1, 1)];

    test('amount 0 returns base unchanged', () {
      final result = lerpCurve(base, target, 0);
      expect(result, base);
    });

    test('amount 1 returns target unchanged', () {
      final result = lerpCurve(base, target, 1);
      expect(result, target);
    });

    test('amount 0.5 lands halfway between base and target', () {
      final result = lerpCurve(base, target, 0.5);
      expect(result[1].y, closeTo(0.6, 1e-9));
    });

    test('amount 1.5 (150%) overshoots past target', () {
      final result = lerpCurve(base, target, 1.5);
      // base.y=0.4, target.y=0.8, delta=0.4 -> 0.4 + 0.4*1.5 = 1.0
      expect(result[1].y, closeTo(1.0, 1e-9));
    });

    test('mismatched point counts fall back to target unchanged', () {
      const shortBase = [CurvePoint(0, 0), CurvePoint(1, 1)];
      final result = lerpCurve(shortBase, target, 0.5);
      expect(result, target);
    });
  });

  group('lerpPhotoCurves', () {
    test('blends every channel independently', () {
      const base = PhotoCurves(
        tone: [CurvePoint(0, 0), CurvePoint(1, 0.5)],
        red: [CurvePoint(0, 0), CurvePoint(1, 0.2)],
      );
      const target = PhotoCurves(
        tone: [CurvePoint(0, 0), CurvePoint(1, 1.0)],
        red: [CurvePoint(0, 0), CurvePoint(1, 0.6)],
      );
      final result = lerpPhotoCurves(base, target, 0.5);
      expect(result.tone[1].y, closeTo(0.75, 1e-9));
      expect(result.red[1].y, closeTo(0.4, 1e-9));
    });
  });
}
