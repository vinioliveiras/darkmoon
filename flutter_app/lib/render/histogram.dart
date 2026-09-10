/// Per-channel pixel counts across [bins] evenly-spaced buckets over 0-255,
/// matching the Python app's `HistogramWidget` (64 bins, `np.histogram`).
class Histogram {
  const Histogram({
    required this.red,
    required this.green,
    required this.blue,
    this.pixelCount = 0,
    this.clippedHigh = const [0, 0, 0],
    this.clippedLow = const [0, 0, 0],
  });

  final List<int> red;
  final List<int> green;
  final List<int> blue;

  /// Pixels counted, for the clipping fractions below (0 = unknown).
  final int pixelCount;

  /// Pixels at or above [clipHighLevel] per channel (R, G, B) — the
  /// highlight clipping indicators (2026-09-11).
  final List<int> clippedHigh;

  /// Pixels at or below [clipLowLevel] per channel (R, G, B) — the shadow
  /// clipping indicators.
  final List<int> clippedLow;

  /// Fraction of pixels clipped in channel [channel] (0 R, 1 G, 2 B) at
  /// the highlight end, 0 when [pixelCount] is unknown.
  double clippedHighFraction(int channel) =>
      pixelCount == 0 ? 0 : clippedHigh[channel] / pixelCount;

  double clippedLowFraction(int channel) =>
      pixelCount == 0 ? 0 : clippedLow[channel] / pixelCount;
}

/// A channel at or above this (of 255) counts as clipped at the highlight
/// end — 254 rather than 255 so an 8-bit rounding on the way out does not
/// hide a blown pixel, the same level the decode gain cap reads.
const int clipHighLevel = 254;

/// A channel at or below this counts as clipped at the shadow end.
const int clipLowLevel = 1;

const int histogramBins = 64;

/// Bins packed pixel data (0-255) into a 64-bucket per-channel histogram.
/// Cheap enough to compute on every render since it's a single linear pass
/// over data already in hand.
///
/// [channels] is the source's bytes-per-pixel stride: 3 for packed RGB
/// (the CPU pipeline's own buffer shape), 4 for RGBA (what a GPU readback
/// hands back, and what the canvas is fed straight from — see
/// `render_job.dart`'s `RenderResult.previewRgba`). Only the first three
/// bytes of each pixel are ever read either way, so alpha is ignored
/// rather than binned.
Histogram computeHistogram(List<int> rgb, {int channels = 3}) {
  final red = List<int>.filled(histogramBins, 0);
  final green = List<int>.filled(histogramBins, 0);
  final blue = List<int>.filled(histogramBins, 0);
  // 256 / histogramBins (64) is exactly 4, so the bin index is a plain
  // bit shift — no float division/floor/clamp needed per pixel (rgb
  // values are already ints in 0-255, so the result always lands in 0-63
  // on its own). Asserts rather than silently miscomputing if
  // histogramBins ever changes to something this shift no longer matches.
  const binShift = 2; // log2(256 / histogramBins)
  assert(
    1 << binShift == 256 ~/ histogramBins,
    'binShift must be updated to match histogramBins',
  );
  final high = [0, 0, 0];
  final low = [0, 0, 0];
  var pixels = 0;
  for (var i = 0; i + 2 < rgb.length; i += channels) {
    final r = rgb[i];
    final g = rgb[i + 1];
    final b = rgb[i + 2];
    red[r >> binShift]++;
    green[g >> binShift]++;
    blue[b >> binShift]++;
    if (r >= clipHighLevel) high[0]++;
    if (g >= clipHighLevel) high[1]++;
    if (b >= clipHighLevel) high[2]++;
    if (r <= clipLowLevel) low[0]++;
    if (g <= clipLowLevel) low[1]++;
    if (b <= clipLowLevel) low[2]++;
    pixels++;
  }
  return Histogram(
    red: red,
    green: green,
    blue: blue,
    pixelCount: pixels,
    clippedHigh: high,
    clippedLow: low,
  );
}
