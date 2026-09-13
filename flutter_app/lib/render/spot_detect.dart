// Magical Repair (2026-09-13, PENDING 48): finds the small blemishes a
// photo should not have — dust on the sensor, specks on a scan, thin
// scratches — without anyone painting over them, so the Remove objects
// tool can fill them all in one go. Detection only; the fill is the
// ordinary removal pipeline (inpaint.dart), which is why the result is a
// removal alpha and not pixels.
//
// A blemish is a pixel that sits far from the median of its 5x5
// neighbourhood (the median ignores a speck, a blur would not), grouped
// into connected components and kept only when the component is small
// and compact (a spot) or thin and long (a scratch) — never a real
// object, which is large in both directions. The threshold follows the
// sensitivity slider.

import 'dart:math' as math;
import 'dart:typed_data';

/// What [detectBlemishes] found: the alpha to remove (1 inside, 0
/// outside, already grown by two pixels) and how many blemishes it holds.
class BlemishMask {
  const BlemishMask({required this.alpha, required this.count});

  final Float32List alpha;
  final int count;
}

/// The residual (0..255 luminance) a pixel must stand off its
/// neighbourhood by, at sensitivity 0 and at sensitivity 1.
const _thresholdAtLow = 30.0;
const _thresholdAtHigh = 9.0;

double _luma(int r, int g, int b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

/// Runs the detector over packed RGB [rgb] of [width] x [height].
/// [sensitivity] is 0..1 (the slider's 0..100 over 100): higher finds
/// fainter specks.
BlemishMask detectBlemishes(
  Uint8List rgb,
  int width,
  int height, {
  double sensitivity = 0.5,
}) {
  final n = width * height;
  final luma = Float32List(n);
  for (var p = 0, i = 0; p < n; p++, i += 3) {
    luma[p] = _luma(rgb[i], rgb[i + 1], rgb[i + 2]);
  }
  final threshold =
      _thresholdAtLow +
      (_thresholdAtHigh - _thresholdAtLow) * sensitivity.clamp(0.0, 1.0);
  // Candidates: far from the 5x5 median.
  final candidate = Uint8List(n);
  final window = Float32List(25);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var k = 0;
      for (var dy = -2; dy <= 2; dy++) {
        final yy = (y + dy).clamp(0, height - 1);
        for (var dx = -2; dx <= 2; dx++) {
          final xx = (x + dx).clamp(0, width - 1);
          window[k++] = luma[yy * width + xx];
        }
      }
      final median = _median25(window);
      final p = y * width + x;
      if ((luma[p] - median).abs() > threshold) {
        candidate[p] = 1;
      }
    }
  }
  // Components: small and compact, or thin and long.
  final longEdge = math.max(width, height);
  final maxArea = math.max(40, (n * 0.0015).round());
  final spotMaxSide = math.max(6, (longEdge * 0.03).round());
  final scratchMaxLength = math.max(spotMaxSide, (longEdge * 0.25).round());
  final labelled = Uint8List(n);
  final alpha = Float32List(n);
  final stack = <int>[];
  var count = 0;
  for (var start = 0; start < n; start++) {
    if (candidate[start] == 0 || labelled[start] != 0) continue;
    // Flood fill collecting the component.
    final members = <int>[];
    stack.add(start);
    labelled[start] = 1;
    var minX = width, maxX = -1, minY = height, maxY = -1;
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      members.add(p);
      final x = p % width, y = p ~/ width;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (members.length > maxArea * 4) {
        // Far too big to be a blemish: stop growing it, drop the rest.
        continue;
      }
      // 8-connected: a diagonal scratch is one blemish, not a row of
      // three-pixel stubs.
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= height) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= width || (dx == 0 && dy == 0)) continue;
          _push(stack, labelled, candidate, yy * width + xx);
        }
      }
    }
    final area = members.length;
    if (area < 2 || area > maxArea) continue;
    final bw = maxX - minX + 1, bh = maxY - minY + 1;
    final longSide = math.max(bw, bh);
    final compact = longSide <= spotMaxSide && area >= 0.3 * bw * bh;
    // Thin by average thickness (a diagonal scratch has a fat bounding
    // box but little area), and long enough not to be a speck.
    final thin =
        area / longSide <= 3.0 && longSide <= scratchMaxLength && longSide >= 6;
    if (!compact && !thin) continue;
    // A blemish sits on its surroundings; the corner or edge of a real
    // object does not. The ring two to three pixels out must be flat
    // next to how far the component stands off it — an object's corner
    // has the object itself in that ring.
    if (!_ringIsFlat(luma, width, height, members, minX, minY, maxX, maxY)) {
      continue;
    }
    for (final p in members) {
      alpha[p] = 1.0;
    }
    count++;
  }
  return BlemishMask(alpha: _grow(alpha, width, height, 2), count: count);
}

bool _ringIsFlat(
  Float32List luma,
  int width,
  int height,
  List<int> members,
  int minX,
  int minY,
  int maxX,
  int maxY,
) {
  const reach = 3;
  final x0 = math.max(0, minX - reach), y0 = math.max(0, minY - reach);
  final x1 = math.min(width - 1, maxX + reach);
  final y1 = math.min(height - 1, maxY + reach);
  final lw = x1 - x0 + 1, lh = y1 - y0 + 1;
  // Distance-to-component in the local box: 0 on it, 1 next to it, ...
  final dist = Uint8List(lw * lh)..fillRange(0, lw * lh, 255);
  final queue = <int>[];
  for (final p in members) {
    final lx = p % width - x0, ly = p ~/ width - y0;
    dist[ly * lw + lx] = 0;
    queue.add(ly * lw + lx);
  }
  for (var qi = 0; qi < queue.length; qi++) {
    final q = queue[qi];
    final d = dist[q];
    if (d >= reach) continue;
    final lx = q % lw, ly = q ~/ lw;
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nx = lx + dx, ny = ly + dy;
      if (nx < 0 || ny < 0 || nx >= lw || ny >= lh) continue;
      final nq = ny * lw + nx;
      if (dist[nq] > d + 1) {
        dist[nq] = d + 1;
        queue.add(nq);
      }
    }
  }
  var compSum = 0.0;
  for (final p in members) {
    compSum += luma[p];
  }
  final compMean = compSum / members.length;
  var ringMin = double.infinity, ringMax = -double.infinity, ringSum = 0.0;
  var ringN = 0;
  for (var ly = 0; ly < lh; ly++) {
    for (var lx = 0; lx < lw; lx++) {
      final d = dist[ly * lw + lx];
      if (d < 2 || d > reach) continue;
      final v = luma[(ly + y0) * width + lx + x0];
      ringMin = math.min(ringMin, v);
      ringMax = math.max(ringMax, v);
      ringSum += v;
      ringN++;
    }
  }
  if (ringN == 0) return false;
  final standOff = (compMean - ringSum / ringN).abs();
  return ringMax - ringMin < 0.6 * standOff;
}

void _push(List<int> stack, Uint8List labelled, Uint8List candidate, int q) {
  if (candidate[q] != 0 && labelled[q] == 0) {
    labelled[q] = 1;
    stack.add(q);
  }
}

/// The median of 25 values, by partial selection (the window is reused,
/// so it may be reordered).
double _median25(Float32List w) {
  // Insertion sort is fine at this size and beats allocating.
  for (var i = 1; i < 25; i++) {
    final v = w[i];
    var j = i - 1;
    while (j >= 0 && w[j] > v) {
      w[j + 1] = w[j];
      j--;
    }
    w[j + 1] = v;
  }
  return w[12];
}

/// [alpha] dilated by [radius] pixels (a square), so the fill reaches a
/// little past the speck's own edge.
Float32List _grow(Float32List alpha, int width, int height, int radius) {
  final out = Float32List(alpha.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = y * width + x;
      if (alpha[p] <= 0) continue;
      for (var dy = -radius; dy <= radius; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= height) continue;
        for (var dx = -radius; dx <= radius; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= width) continue;
          out[yy * width + xx] = 1.0;
        }
      }
    }
  }
  return out;
}

/// `compute` entry: the same detector over a record argument.
BlemishMask detectBlemishesJob(
  ({Uint8List rgb, int width, int height, double sensitivity}) args,
) => detectBlemishes(
  args.rgb,
  args.width,
  args.height,
  sensitivity: args.sensitivity,
);
