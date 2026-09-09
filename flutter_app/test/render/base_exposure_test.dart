import 'package:darkmoon/render/calibration.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// The camera's own brightness for a shot sets where the Exposure
/// slider's zero sits, the same way as-shot white balance sets where
/// Temperature's does. It is a baseline, not an edit, and the difference
/// shows in where it is added.
///
/// It arrives in stops and the slider is in slider units, and this file
/// used to assert that 0.6 stops came out as 0.6 — which is the bug it
/// should have caught. calExposureUnitsPerStop is 12, so the camera's
/// correction was applied at a twelfth of its size: a photo needing -1.5
/// stops got -0.125 and opened blown out. Every assertion here now names
/// the conversion, so the units cannot quietly drift apart again.
void main() {
  test('it shifts the slider zero', () {
    expect(
      RenderParams.fromValues(const {}, baseExposureStops: 0.6).exposure,
      closeTo(0.6 * calExposureUnitsPerStop, 1e-9),
      reason: 'a photo with no exposure edit opens at the camera brightness',
    );
    expect(
      RenderParams.fromValues(const {
        'Exposure': -0.4,
      }, baseExposureStops: 0.6).exposure,
      closeTo(0.6 * calExposureUnitsPerStop - 0.4, 1e-9),
      reason: 'and the slider still reads as a relative adjustment',
    );
  });

  test('without one, nothing changes', () {
    expect(
      RenderParams.fromValues(const {'Exposure': 0.75}).exposure,
      closeTo(0.75, 1e-9),
      reason:
          'every non-RAW source has no camera preview to compare against, '
          'so those must open exactly as they did before',
    );
  });

  test('it is an argument, not a slider value', () {
    // Which is the point. The global Amount slider scales the values map
    // toward its defaults; a baseline scaled that way would make a
    // photo's starting brightness depend on how strongly its edit is
    // being applied. Passing it separately puts it out of that reach.
    const damped = {'Exposure': 1.0};
    final withBase = RenderParams.fromValues(damped, baseExposureStops: 0.5);
    final halfEdit = RenderParams.fromValues(const {
      'Exposure': 0.5,
    }, baseExposureStops: 0.5);
    expect(
      withBase.exposure - halfEdit.exposure,
      closeTo(0.5, 1e-9),
      reason: 'halving the edit must move the result by exactly the edit',
    );
  });

  test('a stop of baseline is a stop of exposure', () {
    // The assertion the old version of this file was missing. A stop has
    // to survive the trip as a stop: the renderer converts with
    // calExposureUnitsPerStop, so anything handed to it in stops has to be
    // multiplied by the same number on the way in.
    for (final stops in [-2.36, -1.5, 0.0, 1.5, 3.29]) {
      expect(
        RenderParams.fromValues(const {}, baseExposureStops: stops).exposure /
            calExposureUnitsPerStop,
        closeTo(stops, 1e-9),
        reason: '$stops stops in has to be $stops stops out',
      );
    }
  });
}
