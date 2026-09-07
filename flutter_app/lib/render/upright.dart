import 'dart:math' as math;
import 'dart:typed_data';

/// Gradient magnitudes below this fraction of the image's strongest are
/// ignored.
///
/// Without a floor, flat sky and sensor noise contribute a very large
/// number of tiny, randomly-oriented votes — enough to bury a real horizon
/// in a photo that is mostly smooth.
const double _magnitudeFloor = 0.12;

/// Converts packed RGB (three bytes per pixel) to luma.
///
/// Rec. 709 weights, the same ones the render pipeline uses everywhere
/// else, so "brightness" means one thing across the app.
Uint8List rgbToLuma(Uint8List rgb, int width, int height) {
  final out = Uint8List(width * height);
  for (var i = 0, p = 0; p < out.length; i += 3, p++) {
    out[p] = (0.2126 * rgb[i] + 0.7152 * rgb[i + 1] + 0.0722 * rgb[i + 2])
        .round()
        .clamp(0, 255);
  }
  return out;
}

/// How far [angleDeg] sits from the nearest multiple of 90, signed.
///
/// Returns a value in (-45, 45].
double deviationFromAxis(double angleDeg) {
  var deviation = angleDeg % 90.0;
  if (deviation > 45.0) {
    deviation -= 90.0;
  }
  return deviation;
}

/// The rotation, in degrees, that would level [luma] — or null when
/// nothing in the frame is straight enough to trust.
///
/// The analysis half of the Upright modes (PENDING item 27); Level is the
/// first of them to use it.
///
/// Works in **4-theta space**: every edge direction is quadrupled before
/// being averaged. That is the natural space for this question. Edge
/// orientation is periodic every 180 degrees and "distance from the
/// nearest axis" every 90, so quadrupling makes both wraparounds vanish —
/// a horizon at 5 degrees and a building's verticals at 95 land on the
/// same point and reinforce each other rather than cancelling. The average
/// is then a plain circular mean: no bins, no peak finding, no
/// interpolation.
///
/// That last part is where the accuracy comes from, and it was not the
/// first attempt. An orientation histogram with parabolic peak
/// interpolation — the more obvious approach — read a 5 degree tilt as
/// 4.09 and sometimes split one edge into two peaks. It was removed rather
/// than kept alongside this: two measurements of the same quantity, one of
/// them known to be worse, is how the wrong one ends up being used.
///
/// [tolerance] is how far from an axis the answer may be and still be
/// believed. Beyond it the photo's straight edges are taken to be
/// genuinely diagonal — a roof, a road — and levelling to them would tilt
/// the photo rather than fix it.
///
/// [minConfidence] is the resultant length of the circular mean, 0 to 1:
/// how much the edges agree with one another. Foliage scatters across
/// every direction and lands near zero.
///
/// Null is a real answer and the caller has to handle it. Inventing a
/// rotation for a photo with nothing straight in it is worse than leaving
/// it alone.
double? levelRotationFor(
  Uint8List luma,
  int width,
  int height, {
  double tolerance = 12.0,
  double minConfidence = 0.35,
}) {
  // Ignore a thin border. An edge that runs out of the frame is cut off by
  // it, and that cut is itself an edge lying exactly along the frame, at 0
  // or 90 degrees. Those caps vote for "already level" and drag the
  // estimate toward zero — about a third of a degree on a 6 degree tilt,
  // which is more than the whole correction is allowed to be wrong by.
  final margin = math.max(2, math.min(width, height) ~/ 100);
  if (width <= margin * 2 || height <= margin * 2) {
    return null;
  }

  var strongest = 0.0;
  final magnitudes = Float64List(width * height);
  final angles = Float64List(width * height);
  for (var y = margin; y < height - margin; y++) {
    for (var x = margin; x < width - margin; x++) {
      final i = y * width + x;
      final tl = luma[i - width - 1];
      final t = luma[i - width];
      final tr = luma[i - width + 1];
      final l = luma[i - 1];
      final r = luma[i + 1];
      final bl = luma[i + width - 1];
      final b = luma[i + width];
      final br = luma[i + width + 1];

      // Scharr, not Sobel. Sobel's 3x3 kernel is not rotationally
      // symmetric and its angle estimate is biased for edges away from
      // the axes — measured here as a consistent 4.7% underestimate,
      // which turned a 6 degree tilt into 5.72 no matter how many edges
      // the frame held. Scharr's weights are the ones chosen to minimise
      // exactly that error, and angle is the only thing this function
      // computes.
      final gx = 3 * (tr + br) + 10 * r - 3 * (tl + bl) - 10 * l;
      final gy = 3 * (bl + br) + 10 * b - 3 * (tl + tr) - 10 * t;
      final magnitude = math.sqrt(gx * gx + gy * gy);
      magnitudes[i] = magnitude;
      if (magnitude > strongest) {
        strongest = magnitude;
      }
      // An edge runs perpendicular to its own gradient.
      angles[i] = math.atan2(gy, gx) + math.pi / 2;
    }
  }
  if (strongest <= 0) {
    return null;
  }

  final floor = strongest * _magnitudeFloor;
  var sumCos = 0.0;
  var sumSin = 0.0;
  var sumWeight = 0.0;
  for (var i = 0; i < magnitudes.length; i++) {
    final magnitude = magnitudes[i];
    if (magnitude < floor) {
      continue;
    }
    // Weighted by magnitude: a long hard horizon should outvote a scatter
    // of soft texture edges that happen to agree with each other.
    final quadrupled = 4 * angles[i];
    sumCos += magnitude * math.cos(quadrupled);
    sumSin += magnitude * math.sin(quadrupled);
    sumWeight += magnitude;
  }
  if (sumWeight <= 0) {
    return null;
  }

  final confidence = math.sqrt(sumCos * sumCos + sumSin * sumSin) / sumWeight;
  if (confidence < minConfidence) {
    return null;
  }

  final deviation = math.atan2(sumSin, sumCos) / 4 * 180.0 / math.pi;
  if (deviation.abs() > tolerance) {
    return null;
  }
  return -deviation;
}
