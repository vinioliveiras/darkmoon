import 'package:darkmoon/render/mask.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// The CPU and GPU mask paths each used to build a mask layer's params
/// themselves, and drifted: the GPU copy left renderScale out, so every
/// mask rendered its neighbourhood stages as if the frame were the
/// reference size however big it really was. On an export-sized frame
/// that made a mask's Sharpen do nothing at all.
///
/// They share one builder now. These are the properties that made the
/// difference, asserted where they can run without a GPU.
void main() {
  const mask = MaskLayer(
    id: 'm1',
    name: 'Mask',
    type: MaskType.radialGradient,
    values: {'Clarity': 40, 'Exposure': 1},
  );

  test('a mask layer renders at the frame it is actually on', () {
    final global = const RenderParams().withRenderScaleFor(3000, 2000);
    expect(
      global.renderScale,
      greaterThan(1.0),
      reason: 'a big frame is the case that exposed this',
    );
    expect(
      maskLayerParams(mask, global).renderScale,
      global.renderScale,
      reason:
          'a mask layer renders over the same frame as the global layer, '
          'so its radii have to scale identically',
    );
  });

  test('it carries the mask own values, not the global ones', () {
    final global = const RenderParams(exposure: 5).withRenderScaleFor(1024, 768);
    final params = maskLayerParams(mask, global);
    expect(params.exposure, 1);
    expect(params.clarity, 40);
  });

  test('the base profile curve is the base image alone', () {
    final params = maskLayerParams(
      mask,
      const RenderParams(baseContrast: 80),
    );
    expect(
      params.baseContrast,
      0,
      reason:
          'a mask layer renders over the already-profiled buffer, so '
          'applying it again would double the contrast under the mask',
    );
  });

  test('white balance stays relative to the same as-shot reference', () {
    const global = RenderParams(asShotKelvin: 4200, asShotTint: 12);
    final params = maskLayerParams(mask, global);
    expect(params.asShotKelvin, 4200);
    expect(params.asShotTint, 12);
  });
}
