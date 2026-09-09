import 'package:darkmoon/render/gpu/gpu_pass.dart';
import 'package:flutter_test/flutter_test.dart';

/// The GPU path used to refuse large frames, because box_blur_h/v silently
/// truncate above [gpuMaxBoxBlurRadius] — their loop bound has to be a
/// compile-time constant — and Dehaze's sigma-40 blur outgrows that at
/// about 3100px. Every settled render on a modern sensor went to the CPU.
///
/// runBoxBlurGpu computes a blur too wide for the shaders on a smaller
/// copy now, so the cap bounds one pass instead of the whole pipeline.
/// These are the cases that used to be refused.
void main() {
  double scaleFor(int sensorLongEdge, int fullQualityPercent) =>
      sensorLongEdge * fullQualityPercent / 100 / 1024.0;

  test('a full-sensor render is no longer sent to the CPU', () {
    // 7728px at 100% is scale 7.55, which needs a Dehaze radius of about
    // 302 against a shader cap of 128. That is what the pyramid is for.
    expect(gpuCanRenderAtScale(scaleFor(7728, 100)), isTrue);
    expect(gpuCanRenderAtScale(scaleFor(7728, 60)), isTrue);
  });

  test('ordinary preview resolutions still fit, unchanged', () {
    expect(gpuCanRenderAtScale(1.0), isTrue);
    expect(gpuCanRenderAtScale(2.0), isTrue);
    for (final preview in [512, 768, 1024, 1280, 1600, 2048]) {
      expect(gpuCanRenderAtScale(preview / 1024.0), isTrue);
    }
  });

  test('the shader cap itself is unchanged', () {
    // The pyramid works around this number; it does not raise it. A change
    // here means the shaders themselves changed, and the factor choice in
    // _pyramidBoxBlurGpu is derived from it.
    expect(gpuMaxBoxBlurRadius, 128);
  });
}
