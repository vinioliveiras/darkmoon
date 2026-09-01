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
    // Fujifilm X100VI cam_xyz (from tool/wb_dump.dart). The estimate must
    // land near Meridian's own "As Shot" readout — checked against four
    // real files below (Kelvin within ~2%, Tint within ~4 units).
    const fujiCamXyz = [
      [1.1809, -0.5358, -0.1141],
      [-0.4248, 1.2164, 0.2343],
      [-0.0514, 0.1097, 0.5848],
    ];

    // (camMul, MeridianKelvin, MeridianTint)
    const fujiRefs = [
      ([515.0, 302.0, 428.0, 0.0], 5550.0, -42.0), // _DSF1337 (van)
      ([501.0, 302.0, 347.0, 0.0], 7300.0, -87.0), // _DSF1273 (hose)
      ([608.0, 302.0, 488.0, 0.0], 5650.0, 4.0), //  _DSF1363 (near-neutral)
      ([570.0, 302.0, 305.0, 0.0], 13500.0, -80.0), // _DSF1312 (blue hour)
    ];

    for (final (camMul, lrKelvin, lrTint) in fujiRefs) {
      test('matches Meridian for cam_mul $camMul ($lrKelvin K / $lrTint)', () {
        final res = wbMultipliersToKelvinTint(camMul, camXyz: fujiCamXyz);
        expect(res.kelvin, closeTo(lrKelvin, lrKelvin * 0.03));
        expect(res.tint, closeTo(lrTint, 5));
      });
    }

    test('a bluer as-shot (cool scene) reads warmer Kelvin', () {
      final cool = wbMultipliersToKelvinTint(
        [640.0, 302.0, 360.0, 0.0],
        camXyz: fujiCamXyz,
      );
      final warm = wbMultipliersToKelvinTint(
        [360.0, 302.0, 640.0, 0.0],
        camXyz: fujiCamXyz,
      );
      expect(cool.kelvin, greaterThan(warm.kelvin));
    });

    test('falls back to the WBCT table when there is no camera matrix', () {
      final res = wbMultipliersToKelvinTint(
        [1.6, 1.0, 1.6, 1.0],
        wbctCoeffs: const [
          [3000, 1.2, 1.0, 2.2, 1.0],
          [6500, 2.2, 1.0, 1.2, 1.0],
        ],
      );
      expect(res.kelvin, inInclusiveRange(3500, 5500));
    });

    test('falls back to 5500/0 with no data at all', () {
      final res = wbMultipliersToKelvinTint([0, 0, 0, 0]);
      expect(res.kelvin, 5500);
      expect(res.tint, 0);
    });
  });
}
