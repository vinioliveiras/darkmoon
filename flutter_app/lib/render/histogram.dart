/// Per-channel pixel counts across [bins] evenly-spaced buckets over 0-255,
/// matching the Python app's `HistogramWidget` (64 bins, `np.histogram`).
class Histogram {
  const Histogram({required this.red, required this.green, required this.blue});

  final List<int> red;
  final List<int> green;
  final List<int> blue;
}

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
  for (var i = 0; i + 2 < rgb.length; i += channels) {
    red[rgb[i] >> binShift]++;
    green[rgb[i + 1] >> binShift]++;
    blue[rgb[i + 2] >> binShift]++;
  }
  return Histogram(red: red, green: green, blue: blue);
}
