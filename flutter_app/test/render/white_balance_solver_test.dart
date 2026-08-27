import 'dart:typed_data';

import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/white_balance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('solveNeutralizingTempTint', () {
    // Render a flat gray patch through the WB step with a known Temp/Tint,
    // then check the solver recovers a Temp/Tint that neutralizes it.
    ({double r, double g, double b}) wbApplied(
      double temperature,
      double tint, {
      double asShotKelvin = 5500,
      double asShotTint = 0,
    }) {
      final src = Uint8List(3 * 4)..fillRange(0, 12, 150);
      final out = renderRgb(
        2,
        2,
        src,
        RenderParams(
          temperature: temperature,
          tint: tint,
          asShotKelvin: asShotKelvin,
          asShotTint: asShotTint,
        ),
      );
      return (r: out[0].toDouble(), g: out[1].toDouble(), b: out[2].toDouble());
    }

    test('recovers the inverse of a known warm+magenta shift', () {
      final shifted = wbApplied(6500, 30);
      final solved = solveNeutralizingTempTint(
        shifted.r,
        shifted.g,
        shifted.b,
        asShotKelvin: 5500,
        asShotTint: 0,
      );
      // Applying the solved values to the shifted patch should bring it
      // back near neutral gray.
      final src = Uint8List(3)
        ..[0] = shifted.r.round()
        ..[1] = shifted.g.round()
        ..[2] = shifted.b.round();
      final back = renderRgb(
        1,
        1,
        src,
        RenderParams(
          temperature: solved.kelvin,
          tint: solved.tint,
          asShotKelvin: 5500,
          asShotTint: 0,
        ),
      );
      expect((back[0] - back[1]).abs(), lessThan(3));
      expect((back[1] - back[2]).abs(), lessThan(3));
    });

    test('a bluish sample warms (kelvin > as-shot), a greenish sample '
        'pushes tint toward magenta (positive)', () {
      final bluish = solveNeutralizingTempTint(
        120,
        150,
        190,
        asShotKelvin: 5500,
        asShotTint: 0,
      );
      expect(bluish.kelvin, greaterThan(5500));

      final greenish = solveNeutralizingTempTint(
        150,
        190,
        150,
        asShotKelvin: 5500,
        asShotTint: 0,
      );
      expect(greenish.tint, greaterThan(0));
    });

    test('grayWorldTempTint on a neutral image returns ~as-shot', () {
      final rgb = Uint8List(300)..fillRange(0, 300, 128);
      final res = grayWorldTempTint(
        rgb,
        asShotKelvin: 5200,
        asShotTint: 4,
      );
      expect(res.kelvin, closeTo(5200, 50));
      expect(res.tint, closeTo(4, 2));
    });
  });

  group('wbMultipliersToKelvinTint', () {
    test('a daylight-ish cam_mul lands in a plausible band', () {
      final res = wbMultipliersToKelvinTint(
        [2.0, 1.0, 1.5, 1.0],
        const [
          [0.4124, 0.3576, 0.1805],
          [0.2126, 0.7152, 0.0722],
          [0.0193, 0.1192, 0.9505],
        ],
      );
      expect(res.kelvin, inInclusiveRange(3500, 9000));
      expect(res.tint, inInclusiveRange(-150, 150));
    });

    test('falls back to 5500/0 on unset multipliers', () {
      final res = wbMultipliersToKelvinTint([0, 0, 0, 0], const []);
      expect(res.kelvin, 5500);
      expect(res.tint, 0);
    });
  });
}
