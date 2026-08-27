import 'dart:math' as math;

/// Converts one normalized sRGB component to scene-linear light.
double srgbToLinear(double value) {
  final c = value.clamp(0.0, 1.0);
  if (c == 0.0 || c == 1.0) return c;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// Converts one scene-linear component to normalized sRGB.
double linearToSrgb(double value) {
  final c = value.clamp(0.0, 1.0);
  if (c == 0.0 || c == 1.0) return c;
  return c <= 0.0031308
      ? c * 12.92
      : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;
}

/// Converts packed RGB bytes to normalized scene-linear RGB values.
List<double> rgbBytesToLinear(List<int> bytes) => [
      for (final value in bytes) srgbToLinear(value / 255.0),
    ];

/// Converts normalized scene-linear RGB values to packed RGB bytes.
List<int> linearToRgbBytes(List<double> values) => [
      for (final value in values) (linearToSrgb(value) * 255.0).round(),
    ];
