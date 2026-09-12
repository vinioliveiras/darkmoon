import 'dart:math' as math;
import 'dart:typed_data';

/// Fills a hole: [imageChw] is the window around it as a CHW float tensor
/// in 0..1, [maskHw] the hole as 1.0 and everything else 0.0, both
/// `modelSize` square; the answer is the window painted, CHW in 0..255.
/// This is what the LaMa session does (`edit_source_inpaint.dart`),
/// injected so the geometry here runs without a native dependency, the
/// same way `colorize.dart` takes its model.
typedef InpaintModel =
    Float32List Function(Float32List imageChw, Float32List maskHw);

/// Coverage from which a pixel counts as part of the hole the model is
/// asked to paint. Low on purpose: the brush's soft edge has to be inside
/// the hole, or the model leaves those pixels as they were and the blend
/// by coverage below has nothing to fade in — the edge would be a hard
/// cut at the threshold instead of the feather the brush drew.
const inpaintHoleThreshold = 0.05;

/// The rows and columns where [alpha] reaches [threshold], as inclusive
/// pixel bounds, or null when it reaches it nowhere.
({int left, int top, int right, int bottom})? maskBounds(
  Float32List alpha,
  int width,
  int height, {
  double threshold = inpaintHoleThreshold,
}) {
  var left = width, top = height, right = -1, bottom = -1;
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      if (alpha[row + x] >= threshold) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  if (right < 0) {
    return null;
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

/// Removes what [alpha] covers from [rgb] (packed RGB, 0..255) by asking
/// [runModel] to repaint it from its surroundings, and returns the
/// repainted copy; the input is not touched, and comes back as is when
/// [alpha] covers nothing.
///
/// The model sees one fixed-size window, not the photo: a square around
/// the coverage with a margin of [margin] times the coverage's longer
/// side (at least [minMargin] px) so it has context to continue, cut
/// down to the photo where it would overhang, and resampled to
/// [modelSize]. The margin is Solstice's (1.5 times the hole, never
/// under 128 px): more surroundings than the hole itself, which is what
/// the model continues from. The answer is resampled back onto the window and mixed
/// in by [alpha] itself, so a brush's soft edge fades the fill in rather
/// than cutting it. Pixels the brush did not reach keep their bytes.
///
/// A hole much bigger than [modelSize] is filled from a downscaled
/// window and comes back softer than its surroundings — the price of a
/// fixed-resolution model; a cheaper price than tiling a hole the model
/// cannot see whole.
Uint8List inpaintRegion(
  Uint8List rgb,
  int width,
  int height,
  Float32List alpha, {
  required InpaintModel runModel,
  int modelSize = 512,
  double threshold = inpaintHoleThreshold,
  double margin = 1.5,
  int minMargin = 128,
}) {
  final bounds = maskBounds(alpha, width, height, threshold: threshold);
  if (bounds == null) {
    return rgb;
  }
  final bw = bounds.right - bounds.left + 1;
  final bh = bounds.bottom - bounds.top + 1;
  final longer = math.max(bw, bh);
  final pad = math.max(minMargin, (margin * longer).round());
  final side = longer + 2 * pad;
  final rw = math.min(side, width);
  final rh = math.min(side, height);
  final cx = (bounds.left + bounds.right) / 2;
  final cy = (bounds.top + bounds.bottom) / 2;
  final x0 = (cx - rw / 2).round().clamp(0, width - rw);
  final y0 = (cy - rh / 2).round().clamp(0, height - rh);

  // The window, resampled to the model's square: the image as CHW floats
  // in 0..1, the hole as a binary plane.
  final n = modelSize * modelSize;
  final imageChw = Float32List(3 * n);
  final maskHw = Float32List(n);
  for (var dy = 0; dy < modelSize; dy++) {
    final sy = (dy + 0.5) * rh / modelSize - 0.5 + y0;
    for (var dx = 0; dx < modelSize; dx++) {
      final sx = (dx + 0.5) * rw / modelSize - 0.5 + x0;
      final di = dy * modelSize + dx;
      final (r, g, b) = _sampleRgb(rgb, width, height, sx, sy);
      imageChw[di] = r / 255.0;
      imageChw[n + di] = g / 255.0;
      imageChw[2 * n + di] = b / 255.0;
      maskHw[di] = _sampleAlpha(alpha, width, height, sx, sy) >= threshold
          ? 1.0
          : 0.0;
    }
  }

  final painted = runModel(imageChw, maskHw);

  // Back onto the window, mixed in by the brush's own coverage.
  final out = Uint8List.fromList(rgb);
  for (var ry = 0; ry < rh; ry++) {
    final y = y0 + ry;
    final my = (ry + 0.5) * modelSize / rh - 0.5;
    for (var rx = 0; rx < rw; rx++) {
      final x = x0 + rx;
      final idx = y * width + x;
      final a = alpha[idx].clamp(0.0, 1.0);
      if (a <= 0) {
        continue;
      }
      final mx = (rx + 0.5) * modelSize / rw - 0.5;
      final p = idx * 3;
      for (var c = 0; c < 3; c++) {
        final fill = _sampleChannel(
          painted,
          c * n,
          modelSize,
          modelSize,
          mx,
          my,
        );
        final orig = out[p + c].toDouble();
        out[p + c] = (orig + (fill - orig) * a).round().clamp(0, 255);
      }
    }
  }
  return out;
}

(double, double, double) _sampleRgb(
  Uint8List rgb,
  int width,
  int height,
  double x,
  double y,
) {
  final x0 = x.floor().clamp(0, width - 1);
  final y0 = y.floor().clamp(0, height - 1);
  final x1 = (x0 + 1).clamp(0, width - 1);
  final y1 = (y0 + 1).clamp(0, height - 1);
  final fx = (x - x0).clamp(0.0, 1.0);
  final fy = (y - y0).clamp(0.0, 1.0);
  double lerp(int c) {
    final a =
        rgb[(y0 * width + x0) * 3 + c] * (1 - fx) +
        rgb[(y0 * width + x1) * 3 + c] * fx;
    final b =
        rgb[(y1 * width + x0) * 3 + c] * (1 - fx) +
        rgb[(y1 * width + x1) * 3 + c] * fx;
    return a * (1 - fy) + b * fy;
  }

  return (lerp(0), lerp(1), lerp(2));
}

double _sampleAlpha(
  Float32List alpha,
  int width,
  int height,
  double x,
  double y,
) => _sampleChannel(alpha, 0, width, height, x, y);

/// Bilinear sample of one plane of [data] starting at [offset].
double _sampleChannel(
  Float32List data,
  int offset,
  int width,
  int height,
  double x,
  double y,
) {
  final x0 = x.floor().clamp(0, width - 1);
  final y0 = y.floor().clamp(0, height - 1);
  final x1 = (x0 + 1).clamp(0, width - 1);
  final y1 = (y0 + 1).clamp(0, height - 1);
  final fx = (x - x0).clamp(0.0, 1.0);
  final fy = (y - y0).clamp(0.0, 1.0);
  final a =
      data[offset + y0 * width + x0] * (1 - fx) +
      data[offset + y0 * width + x1] * fx;
  final b =
      data[offset + y1 * width + x0] * (1 - fx) +
      data[offset + y1 * width + x1] * fx;
  return a * (1 - fy) + b * fy;
}
