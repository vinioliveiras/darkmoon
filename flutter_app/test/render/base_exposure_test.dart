import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// The camera's own brightness for a shot sets where the Exposure
/// slider's zero sits, the same way as-shot white balance sets where
/// Temperature's does. It is a baseline, not an edit, and the difference
/// shows in where it is added.
void main() {
  test('it shifts the slider zero', () {
    expect(
      RenderParams.fromValues(const {}, baseExposure: 0.6).exposure,
      closeTo(0.6, 1e-9),
      reason: 'a photo with no exposure edit opens at the camera brightness',
    );
    expect(
      RenderParams.fromValues(
        const {'Exposure': -0.4},
        baseExposure: 0.6,
      ).exposure,
      closeTo(0.2, 1e-9),
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
    final withBase = RenderParams.fromValues(damped, baseExposure: 0.5);
    final halfEdit = RenderParams.fromValues(
      const {'Exposure': 0.5},
      baseExposure: 0.5,
    );
    expect(
      withBase.exposure - halfEdit.exposure,
      closeTo(0.5, 1e-9),
      reason: 'halving the edit must move the result by exactly the edit',
    );
  });
}
