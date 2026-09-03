import 'package:darkmoon/render/gpu/gpu_pass.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Radii scale with the frame now, and box_blur_h/v silently truncate
  // above gpuMaxBoxBlurRadius because their loop bound must be a
  // compile-time constant. This is the guard that sends such a render to
  // the CPU instead; getting it wrong means quietly wrong blurs on exactly
  // the largest, most-detailed previews.
  //
  // The numbers below are the real cases: a 7728px sensor (Fujifilm
  // X100VI) at each Dynamic Full Resolution setting, where the render's
  // long edge is fullQualityPercent% of the sensor and the scale is that
  // over calRadiusReferenceLongEdge (1024).
  double scaleFor(int sensorLongEdge, int fullQualityPercent) =>
      sensorLongEdge * fullQualityPercent / 100 / 1024.0;

  test('the default full-quality setting still fits on GPU', () {
    // 40% of 7728 -> scale 3.02 -> Dehaze radius 121, just under the cap.
    expect(gpuCanRenderAtScale(scaleFor(7728, 40)), isTrue);
  });

  test('a higher full-quality setting falls back to CPU', () {
    // 60% -> radius 181, over. Without this guard the blur would be
    // truncated to 128 and silently wrong.
    expect(gpuCanRenderAtScale(scaleFor(7728, 60)), isFalse);
    expect(gpuCanRenderAtScale(scaleFor(7728, 100)), isFalse);
  });

  test('ordinary preview resolutions fit comfortably', () {
    expect(gpuCanRenderAtScale(1.0), isTrue);
    expect(gpuCanRenderAtScale(2.0), isTrue);
    // Every preview resolution the settings offer, on the largest sensor.
    for (final preview in [512, 768, 1024, 1280, 1600, 2048]) {
      expect(
        gpuCanRenderAtScale(preview / 1024.0),
        isTrue,
        reason: 'preview resolution $preview must never need the CPU path',
      );
    }
  });
}
