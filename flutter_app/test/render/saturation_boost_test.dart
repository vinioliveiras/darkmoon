import 'dart:typed_data';

import 'package:darkmoon/render/hsl.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// Camera Color on a file with no camera fit is a saturation lift, and
/// with a fit it is not — the fit rides the profile instead.
void main() {
  double saturationOf(Uint8List rgb) {
    final (_, s, _) = rgbToHsv(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0);
    return s;
  }

  test('the slider lifts saturation when there is no fit', () {
    final source = Uint8List.fromList([180, 120, 100]);
    final plain = renderRgb(1, 1, source, const RenderParams(baseContrast: 0));
    final lifted = renderRgb(
      1,
      1,
      source,
      RenderParams.fromValues(const {'CameraColor': 100}, baseContrast: 0),
    );
    expect(saturationOf(lifted), greaterThan(saturationOf(plain) * 1.15));
  });

  test('with a fit the slider does nothing in this stage', () {
    final params = RenderParams.fromValues(
      const {'CameraColor': 100},
      baseContrast: 0,
      cameraColorHasFit: true,
    );
    expect(params.saturationBoost, 0);
    final without = RenderParams.fromValues(const {}, baseContrast: 0);
    expect(without.saturationBoost, 0);
  });
}
