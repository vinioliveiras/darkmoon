import 'dart:math' as math;
import 'dart:typed_data';

import 'render_params.dart';

/// Absolute color temperature (Kelvin) treated as "no white-balance shift",
/// matching the Python app's TEMPERATURE_NEUTRAL_KELVIN.
const double _temperatureNeutralKelvin = 5500.0;

/// Applies the tonal/color adjustment pipeline to packed 8-bit RGB pixel
/// data (3 bytes/pixel, row-major, no padding) and returns a new buffer of
/// the same shape.
///
/// This is a straight port of the Python app's `render()` — same order of
/// operations, same per-step math — minus Texture, Clarity and Dehaze,
/// which aren't implemented yet (those sliders are accepted but have no
/// effect for now).
///
/// Designed to run via `compute()`: pure function over simple, isolate-
/// transferable data.
Uint8List renderRgb(int width, int height, Uint8List sourceRgb, RenderParams params) {
  final buffer = Float32List(sourceRgb.length);
  for (var i = 0; i < sourceRgb.length; i++) {
    buffer[i] = sourceRgb[i].toDouble();
  }

  final pixelCount = width * height;
  _applyWhiteBalance(buffer, params.temperature, params.tint);
  _applyExposure(buffer, params.exposure);
  _applyBrightnessContrast(buffer, params.brightness, params.contrast);
  _applyHighlightsShadows(buffer, pixelCount, params.highlights, params.shadows);
  _applyWhitesBlacks(buffer, pixelCount, params.whites, params.blacks);
  _applyVibrance(buffer, pixelCount, params.vibrance);
  _applySaturation(buffer, pixelCount, params.saturation);

  final out = Uint8List(sourceRgb.length);
  for (var i = 0; i < buffer.length; i++) {
    out[i] = buffer[i].clamp(0.0, 255.0).round();
  }
  return out;
}

void _applyWhiteBalance(Float32List img, double temperatureKelvin, double tint) {
  final delta = (temperatureKelvin - _temperatureNeutralKelvin) / _temperatureNeutralKelvin * 100.0;
  if (delta == 0 && tint == 0) {
    return;
  }
  final rGain = 1.0 + (delta / 100.0) * 0.3;
  final bGain = 1.0 - (delta / 100.0) * 0.3;
  final gGain = 1.0 - (tint / 100.0) * 0.2;
  for (var i = 0; i < img.length; i += 3) {
    img[i] *= rGain;
    img[i + 1] *= gGain;
    img[i + 2] *= bGain;
  }
}

void _applyExposure(Float32List img, double exposure) {
  if (exposure == 0) {
    return;
  }
  final factor = math.pow(2.0, exposure / 100.0 * 3.0).toDouble();
  for (var i = 0; i < img.length; i++) {
    img[i] *= factor;
  }
}

void _applyBrightnessContrast(Float32List img, double brightness, double contrast) {
  if (brightness == 0 && contrast == 0) {
    return;
  }
  final contrastFactor = 1.0 + contrast / 100.0;
  for (var i = 0; i < img.length; i++) {
    img[i] = (img[i] - 127.5) * contrastFactor + 127.5 + brightness;
  }
}

void _applyHighlightsShadows(Float32List img, int pixelCount, double highlights, double shadows) {
  if (highlights == 0 && shadows == 0) {
    return;
  }
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    // Luminance is computed once from the input and reused for both
    // weights below, matching the Python function (it doesn't recompute
    // luminance after applying the shadows adjustment).
    final luminance = (img[i] + img[i + 1] + img[i + 2]) / 3.0 / 255.0;
    if (shadows != 0) {
      final weight = (1.0 - luminance * 2.0).clamp(0.0, 1.0);
      final add = weight * (shadows / 100.0) * 80.0;
      img[i] += add;
      img[i + 1] += add;
      img[i + 2] += add;
    }
    if (highlights != 0) {
      final weight = ((luminance - 0.5) * 2.0).clamp(0.0, 1.0);
      final add = weight * (highlights / 100.0) * 80.0;
      img[i] += add;
      img[i + 1] += add;
      img[i + 2] += add;
    }
  }
}

void _applyWhitesBlacks(Float32List img, int pixelCount, double whites, double blacks) {
  if (whites == 0 && blacks == 0) {
    return;
  }
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final luminance = (img[i] + img[i + 1] + img[i + 2]) / 3.0 / 255.0;
    if (whites != 0) {
      final weight = ((luminance - 0.75) * 4.0).clamp(0.0, 1.0);
      final add = weight * (whites / 100.0) * 100.0;
      img[i] += add;
      img[i + 1] += add;
      img[i + 2] += add;
    }
    if (blacks != 0) {
      final weight = (1.0 - luminance * 4.0).clamp(0.0, 1.0);
      final add = weight * (blacks / 100.0) * 100.0;
      img[i] += add;
      img[i + 1] += add;
      img[i + 2] += add;
    }
  }
}

void _applyVibrance(Float32List img, int pixelCount, double amount) {
  if (amount == 0) {
    return;
  }
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = img[i], g = img[i + 1], b = img[i + 2];
    final luminance = (r + g + b) / 3.0;
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final currentSaturation = (maxC - minC) / 255.0;
    final factor = 1.0 + (amount / 100.0) * (1.0 - currentSaturation);
    img[i] = luminance + (r - luminance) * factor;
    img[i + 1] = luminance + (g - luminance) * factor;
    img[i + 2] = luminance + (b - luminance) * factor;
  }
}

void _applySaturation(Float32List img, int pixelCount, double amount) {
  if (amount == 0) {
    return;
  }
  final factor = 1.0 + amount / 100.0;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = img[i], g = img[i + 1], b = img[i + 2];
    final luminance = (r + g + b) / 3.0;
    img[i] = luminance + (r - luminance) * factor;
    img[i + 1] = luminance + (g - luminance) * factor;
    img[i + 2] = luminance + (b - luminance) * factor;
  }
}
