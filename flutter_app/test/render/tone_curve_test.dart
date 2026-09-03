import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/tone_curve.dart';

void main() {
  group('buildToneCurveLut', () {
    test('the default 2-point identity curve is a true straight line', () {
      final lut = buildToneCurveLut(identityToneCurve);
      for (var i = 0; i < 256; i++) {
        expect(lut[i], i, reason: 'lut[$i]');
      }
    });

    // Regression lock for the bug documented in render_gpu.dart's
    // `_identityLut` comment: the previous Catmull-Rom spline duplicated
    // each end point as its own "before"/"after" neighbor, which made even
    // perfectly collinear points bow into a visible S-curve (~0.203 at
    // x=0.25 instead of 0.25). The monotone Hermite spline that replaced it
    // must reduce to an exact straight line for ANY collinear points, not
    // just the specific default curve.
    test(
      'collinear points (not just the default curve) stay a straight line',
      () {
        const collinear = [
          CurvePoint(0, 0),
          CurvePoint(0.5, 0.5),
          CurvePoint(1, 1),
        ];
        final lut = buildToneCurveLut(collinear);
        for (var i = 0; i < 256; i++) {
          expect(lut[i], closeTo(i, 1), reason: 'lut[$i]');
        }
      },
    );

    // Expected values below were computed from Solstice's apply_curve
    // (the monotone cubic Hermite spline in shader.wgsl) via a reference
    // Python port, independent of tone_curve.dart's implementation.
    test('an S-curve matches Solstice\'s monotone Hermite spline', () {
      const sCurve = [
        CurvePoint(0, 0),
        CurvePoint(0.25, 0.15),
        CurvePoint(0.5, 0.5),
        CurvePoint(0.75, 0.85),
        CurvePoint(1, 1),
      ];
      final lut = buildToneCurveLut(sCurve);

      expect(lut[26], closeTo(13, 1)); // x=0.102 -> y=0.0513
      expect(
        lut[64],
        closeTo(39, 1),
      ); // x=0.251 -> y=0.151 (near control point)
      expect(lut[96], closeTo(80, 1)); // x=0.376 -> y=0.3147
      expect(
        lut[128],
        closeTo(128, 1),
      ); // x=0.502 -> y=0.5028 (near control point)
      expect(lut[230], closeTo(242, 1)); // x=0.902 -> y=0.9505
    });

    test('a monotone increasing curve never overshoots into a decrease', () {
      const sCurve = [
        CurvePoint(0, 0),
        CurvePoint(0.25, 0.15),
        CurvePoint(0.5, 0.5),
        CurvePoint(0.75, 0.85),
        CurvePoint(1, 1),
      ];
      final lut = buildToneCurveLut(sCurve);
      for (var i = 1; i < 256; i++) {
        expect(
          lut[i],
          greaterThanOrEqualTo(lut[i - 1]),
          reason: 'lut[$i]=${lut[i]} vs lut[${i - 1}]=${lut[i - 1]}',
        );
      }
    });
  });
}
