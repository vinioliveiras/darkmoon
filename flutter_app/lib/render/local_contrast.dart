import 'dart:typed_data';

import 'blur.dart';

/// Boosts (or reduces) high-frequency detail by adding back a fraction of
/// `image - blur(image)` — a classic unsharp-mask-style local contrast
/// effect. Used for both Texture (small [sigma], no midtone protection) and
/// Clarity (large [sigma], [protectMidtones] true so flat skin/sky areas
/// aren't dragged around as hard as edges).
///
/// Ports the Python app's `apply_local_contrast`. Operates in place on a
/// packed RGB [Float32List] (3 values/pixel).
void applyLocalContrast(
  Float32List img,
  int width,
  int height,
  double amount,
  double sigma, {
  bool protectMidtones = false,
}) {
  if (amount == 0) {
    return;
  }
  final pixelCount = width * height;
  Float32List? weight;
  if (protectMidtones) {
    weight = Float32List(pixelCount);
    for (var p = 0; p < pixelCount; p++) {
      final i = p * 3;
      final luminance = (img[i] + img[i + 1] + img[i + 2]) / 3.0 / 255.0;
      weight[p] = (1.0 - (luminance - 0.5).abs() * 2.0).clamp(0.15, 1.0);
    }
  }

  final factor = amount / 100.0;
  for (var channelIndex = 0; channelIndex < 3; channelIndex++) {
    final channel = Float32List(pixelCount);
    for (var p = 0; p < pixelCount; p++) {
      channel[p] = img[p * 3 + channelIndex];
    }
    final blurred = gaussianBlurChannel(channel, width, height, sigma);
    for (var p = 0; p < pixelCount; p++) {
      var highFreq = channel[p] - blurred[p];
      if (protectMidtones) {
        highFreq *= weight![p];
      }
      img[p * 3 + channelIndex] = channel[p] + highFreq * factor;
    }
  }
}
