/// Per-channel pixel counts across [bins] evenly-spaced buckets over 0-255,
/// matching the Python app's `HistogramWidget` (64 bins, `np.histogram`).
class Histogram {
  const Histogram({required this.red, required this.green, required this.blue});

  final List<int> red;
  final List<int> green;
  final List<int> blue;
}

const int histogramBins = 64;

/// Bins packed RGB pixel data (3 bytes/pixel, 0-255) into a 64-bucket
/// per-channel histogram. Cheap enough to compute on every render since
/// it's a single linear pass over data already in hand.
Histogram computeHistogram(List<int> rgb) {
  final red = List<int>.filled(histogramBins, 0);
  final green = List<int>.filled(histogramBins, 0);
  final blue = List<int>.filled(histogramBins, 0);
  const binSize = 256 / histogramBins;
  for (var i = 0; i + 2 < rgb.length; i += 3) {
    red[(rgb[i] / binSize).floor().clamp(0, histogramBins - 1)]++;
    green[(rgb[i + 1] / binSize).floor().clamp(0, histogramBins - 1)]++;
    blue[(rgb[i + 2] / binSize).floor().clamp(0, histogramBins - 1)]++;
  }
  return Histogram(red: red, green: green, blue: blue);
}
