import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/color_space.dart';

void main() {
  test('sRGB transfer functions round-trip representative values', () {
    for (final value in [0.0, 0.001, 0.018, 0.18, 0.5, 1.0]) {
      expect(linearToSrgb(srgbToLinear(value)), closeTo(value, 1e-9));
    }
  });

  test('packed RGB conversion round-trips within byte rounding', () {
    const source = [0, 1, 12, 64, 128, 200, 255];
    expect(linearToRgbBytes(rgbBytesToLinear(source)), source);
  });

  test('conversion clamps out-of-range values', () {
    expect(srgbToLinear(-1), 0);
    expect(srgbToLinear(2), 1);
    expect(linearToSrgb(-1), 0);
    expect(linearToSrgb(2), 1);
  });
}
