import 'dart:math' as math;
import 'dart:typed_data';

import 'blur.dart';

Float32List _minAcrossChannels(Float32List rgb, int pixelCount) {
  final out = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    var m = rgb[i];
    if (rgb[i + 1] < m) {
      m = rgb[i + 1];
    }
    if (rgb[i + 2] < m) {
      m = rgb[i + 2];
    }
    out[p] = m;
  }
  return out;
}

/// A single-image haze removal / addition effect based on the dark-channel
/// prior (He, Sun & Tang), matching the Python app's `apply_dehaze`:
/// estimate atmospheric light from the pixels least likely to be haze-free
/// (largest dark-channel value), derive a transmission map, then invert the
/// haze model to recover the scene (positive [amount]) or blend toward the
/// atmospheric light to add haze (negative [amount]).
///
/// Operates in place on a packed RGB [Float32List] (3 values/pixel, 0-255).
void applyDehaze(Float32List img, int width, int height, double amount) {
  if (amount == 0) {
    return;
  }
  final pixelCount = width * height;
  final norm = Float32List(img.length);
  for (var i = 0; i < img.length; i++) {
    norm[i] = img[i] / 255.0;
  }
  final strength = amount / 100.0;

  final darkChannel = minFilter(
    _minAcrossChannels(norm, pixelCount),
    width,
    height,
    15,
  );

  // Atmospheric light: per-channel max among the 0.1% of pixels with the
  // largest dark-channel value (the pixels least likely to be in shadow or
  // deeply saturated color, i.e. most likely to be pure haze/sky).
  final numPixels = math.max((pixelCount * 0.001).toInt(), 1);
  final orderedByDarkChannel = List<int>.generate(pixelCount, (i) => i)
    ..sort((a, b) => darkChannel[a].compareTo(darkChannel[b]));
  final atmosphericLight = Float32List(3);
  for (var c = 0; c < 3; c++) {
    var maxV = 0.0;
    for (var k = pixelCount - numPixels; k < pixelCount; k++) {
      final v = norm[orderedByDarkChannel[k] * 3 + c];
      if (v > maxV) {
        maxV = v;
      }
    }
    atmosphericLight[c] = maxV.clamp(0.5, 1.0);
  }

  final normalizedByAtm = Float32List(norm.length);
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    normalizedByAtm[i] = norm[i] / atmosphericLight[0];
    normalizedByAtm[i + 1] = norm[i + 1] / atmosphericLight[1];
    normalizedByAtm[i + 2] = norm[i + 2] / atmosphericLight[2];
  }
  final normalizedDark = minFilter(
    _minAcrossChannels(normalizedByAtm, pixelCount),
    width,
    height,
    15,
  );

  final preTransmission = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    preTransmission[p] = 1.0 - 0.9 * normalizedDark[p];
  }
  final transmission = boxBlurMean(preTransmission, width, height, 20);
  for (var p = 0; p < pixelCount; p++) {
    transmission[p] = transmission[p].clamp(0.2, 1.0);
  }

  if (strength >= 0) {
    for (var p = 0; p < pixelCount; p++) {
      final t = 1.0 - strength * (1.0 - transmission[p]);
      final i = p * 3;
      img[i] =
          ((norm[i] - atmosphericLight[0]) / t + atmosphericLight[0]) * 255.0;
      img[i + 1] =
          ((norm[i + 1] - atmosphericLight[1]) / t + atmosphericLight[1]) *
          255.0;
      img[i + 2] =
          ((norm[i + 2] - atmosphericLight[2]) / t + atmosphericLight[2]) *
          255.0;
    }
  } else {
    final hazeAmount = -strength;
    for (var p = 0; p < pixelCount; p++) {
      final i = p * 3;
      img[i] =
          (norm[i] * (1.0 - hazeAmount) + atmosphericLight[0] * hazeAmount) *
          255.0;
      img[i + 1] =
          (norm[i + 1] * (1.0 - hazeAmount) +
              atmosphericLight[1] * hazeAmount) *
          255.0;
      img[i + 2] =
          (norm[i + 2] * (1.0 - hazeAmount) +
              atmosphericLight[2] * hazeAmount) *
          255.0;
    }
  }
}
