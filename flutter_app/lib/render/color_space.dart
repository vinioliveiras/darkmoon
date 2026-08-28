import 'dart:math' as math;
import 'dart:typed_data';

/// The sRGB transfer functions are evaluated tens of times per pixel
/// across the tone/colour point ops — at 36–40 MP that's a billion-plus
/// `pow()` calls per full-resolution render, which was the dominant cost
/// of an export. They're replaced here with 4096-entry lookup tables plus
/// linear interpolation: the curves are smooth and monotone, so the
/// interpolation error is well under 1/255 (invisible), and a lookup +
/// lerp is ~15× cheaper than `pow`.
const int _lutSize = 4096;

double _srgbToLinearExact(double c) => c <= 0.04045
    ? c / 12.92
    : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _linearToSrgbExact(double c) => c <= 0.0031308
    ? c * 12.92
    : 1.055 * math.pow(c, 1.0 / 2.4).toDouble() - 0.055;

/// Plain power-2.2 "perceptual" gamma (distinct from the piecewise sRGB
/// curves above) — RapidRAW's tone ops (Contrast, Shadows/Whites/Blacks)
/// bounce through it per pixel. Also LUT'd; inputs are clamped to [0, 1].
double _perceptualEncodeExact(double c) => math.pow(c, 1.0 / 2.2).toDouble();
double _perceptualDecodeExact(double c) => math.pow(c, 2.2).toDouble();

Float64List _buildLut(double Function(double) f) {
  final lut = Float64List(_lutSize + 1);
  for (var i = 0; i <= _lutSize; i++) {
    lut[i] = f(i / _lutSize);
  }
  // Pin the endpoints exactly (0 -> 0, 1 -> 1) — the exact formulas can
  // land a rounding ULP off at c == 1, and callers rely on a clamped
  // value coming back as precisely 1.0.
  lut[0] = 0.0;
  lut[_lutSize] = 1.0;
  return lut;
}

final Float64List _srgbToLinearLut = _buildLut(_srgbToLinearExact);
final Float64List _linearToSrgbLut = _buildLut(_linearToSrgbExact);
final Float64List _perceptualEncodeLut = _buildLut(_perceptualEncodeExact);
final Float64List _perceptualDecodeLut = _buildLut(_perceptualDecodeExact);

double _lookup(Float64List lut, double value) {
  final c = value < 0.0 ? 0.0 : (value > 1.0 ? 1.0 : value);
  final p = c * _lutSize;
  final i = p.toInt();
  if (i >= _lutSize) {
    return lut[_lutSize];
  }
  final f = p - i;
  return lut[i] + (lut[i + 1] - lut[i]) * f;
}

/// Converts one normalized sRGB component to scene-linear light.
double srgbToLinear(double value) => _lookup(_srgbToLinearLut, value);

/// Converts one scene-linear component to normalized sRGB.
double linearToSrgb(double value) => _lookup(_linearToSrgbLut, value);

/// `pow(value, 1/2.2)` — clamped to [0, 1].
double perceptualEncode(double value) =>
    _lookup(_perceptualEncodeLut, value);

/// `pow(value, 2.2)` — clamped to [0, 1].
double perceptualDecode(double value) =>
    _lookup(_perceptualDecodeLut, value);

/// Converts packed RGB bytes to normalized scene-linear RGB values.
List<double> rgbBytesToLinear(List<int> bytes) => [
      for (final value in bytes) srgbToLinear(value / 255.0),
    ];

/// Converts normalized scene-linear RGB values to packed RGB bytes.
List<int> linearToRgbBytes(List<double> values) => [
      for (final value in values) (linearToSrgb(value) * 255.0).round(),
    ];
