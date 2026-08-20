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
/// [rowOffset] — see [downsampleChannel]'s doc comment — only matters when
/// [img] is a horizontal slice of a larger image (`render_parallel.dart`'s
/// band-parallel rendering) rather than the whole thing (every other
/// caller: leave it at its default 0).
///
/// Designed to run via `compute()`: pure function over simple, isolate-
/// transferable data (same as the rest of render.dart).
void applyBaselineChromaSmoothing(
  Float32List img,
  int width,
  int height, {
  int rowOffset = 0,
}) {
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
  // Chroma tolerates heavy spatial subsampling far better than luminance
  // does — the same reason JPEG/video encoding downsample color 2x-4x
  // (4:2:0) with no visible quality loss on natural photos. This runs
  // unconditionally on every render (there's no slider to turn it off), so
  // at full sensor resolution it used to be the single largest cost in the
  // whole pipeline — denoising at 1/16th the pixels (both dimensions
  // divided by 4, via [_denoiseChromaChannel]) cuts that by roughly the
  // same factor, since box blur's cost is linear in pixel count.
  final denoisedR = _denoiseChromaChannel(
    chromaR,
    width,
    height,
    sigma,
    strength,
    rowOffset,
  );
  final denoisedG = _denoiseChromaChannel(
    chromaG,
    width,
    height,
    sigma,
    strength,
    rowOffset,
  );
  final denoisedB = _denoiseChromaChannel(
    chromaB,
    width,
    height,
    sigma,
    strength,
    rowOffset,
  );

  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final l = luminance[p];
    img[i] = (l + denoisedR[p]).clamp(0.0, 255.0);
    img[i + 1] = (l + denoisedG[p]).clamp(0.0, 255.0);
    img[i + 2] = (l + denoisedB[p]).clamp(0.0, 255.0);
  }
}

/// How much smaller (per dimension) than the working image this pass
/// denoises chroma at — see [applyBaselineChromaSmoothing]'s comment.
const int _downsampleFactor = 4;

/// Downsamples [chroma] by [_downsampleFactor], runs
/// [adaptiveDenoiseChannel] at a proportionally smaller [sigma] (so the
/// blur's real-world radius stays the same as it would be at full
/// resolution), then upsamples the result back to [width]x[height]. Below
/// a `3 * _downsampleFactor` image size, downsampling further wouldn't
/// leave a meaningful buffer to blur, so this just denoises at full
/// resolution instead — the cost only matters for large images anyway.
Float32List _denoiseChromaChannel(
  Float32List chroma,
  int width,
  int height,
  double sigma,
  double strength,
  int rowOffset,
) {
  if (width < _downsampleFactor * 3 || height < _downsampleFactor * 3) {
    return adaptiveDenoiseChannel(chroma, width, height, sigma, strength);
  }
  final small = downsampleChannel(
    chroma,
    width,
    height,
    _downsampleFactor,
    rowOffset: rowOffset,
  );
  final denoisedSmall = adaptiveDenoiseChannel(
    small.channel,
    small.width,
    small.height,
    sigma / _downsampleFactor,
    strength,
  );
  return upsampleChannelNearest(
    denoisedSmall,
    small.width,
    small.height,
    _downsampleFactor,
    width,
    height,
    rowOffset: rowOffset,
  );
}
