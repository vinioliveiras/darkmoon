import 'dart:typed_data';

import 'blur.dart';
import 'luminance.dart';

/// A small, always-applied chroma smoothing pass — mirrors Adobe Camera
/// Raw's own default Color Noise Reduction (~25), which real Lightroom
/// applies to every RAW file whether or not the active preset mentions
/// denoise at all, since it's baked into ACR's default develop settings
/// rather than written into presets/XMP. Without an equivalent baseline
/// here, the same RAW looks chromatically noisier in Darkmoon than in
/// Lightroom even before any user adjustment or AI Denoise level is
/// applied.
///
/// Deliberately not exposed as a slider — same reasoning as the AI Denoise
/// levels being pre-tuned rather than manually dialed in: this is meant to
/// match what Lightroom does invisibly, not add another control. Uses the
/// same locally-calibrated noise-floor estimate as [applyAiDenoise] (via
/// `adaptiveDenoiseChannel`) rather than a flat blend, so it stays this
/// gentle without visibly softening real color detail/edges.
///
/// Designed to run via `compute()`: pure function over simple, isolate-
/// transferable data (same as the rest of render.dart).
void applyBaselineChromaSmoothing(Float32List img, int width, int height) {
  if (width < 3 || height < 3) {
    return;
  }
  final pixelCount = width * height;
  final luminance = Float32List(pixelCount);
  final chromaR = Float32List(pixelCount);
  final chromaG = Float32List(pixelCount);
  final chromaB = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final l = luminanceRgb(img[i], img[i + 1], img[i + 2]);
    luminance[p] = l;
    chromaR[p] = img[i] - l;
    chromaG[p] = img[i + 1] - l;
    chromaB[p] = img[i + 2] - l;
  }

  const sigma = 2.5;
  const strength = 0.4;
  final denoisedR = adaptiveDenoiseChannel(
    chromaR,
    width,
    height,
    sigma,
    strength,
  );
  final denoisedG = adaptiveDenoiseChannel(
    chromaG,
    width,
    height,
    sigma,
    strength,
  );
  final denoisedB = adaptiveDenoiseChannel(
    chromaB,
    width,
    height,
    sigma,
    strength,
  );

  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final l = luminance[p];
    img[i] = (l + denoisedR[p]).clamp(0.0, 255.0);
    img[i + 1] = (l + denoisedG[p]).clamp(0.0, 255.0);
    img[i + 2] = (l + denoisedB[p]).clamp(0.0, 255.0);
  }
}
