import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

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

/// How a [cloneRegion] hole is filled: pixels copied from elsewhere in
/// the frame ([clone]), or copied and then blended into the hole's own
/// lighting so the seam disappears ([heal]).
enum CloneFill { clone, heal }

/// The manual counterpart of [inpaintRegion] — Solstice's Clone and Heal
/// patches (`generate_manual_cleanup_patch`): every pixel the hole covers
/// is taken from the same spot shifted by ([offsetX], [offsetY]) pixels.
///
/// Clone copies those pixels as they are. Heal keeps the source's
/// texture but takes the hole's own colour and lighting from its border:
/// Poisson blending, solved as Solstice does — the boundary holds the
/// destination-minus-source difference, the interior relaxes toward it
/// with successive over-relaxation (omega 1.6), and the result is
/// source + that smooth difference. [iterations] is capped for big holes
/// so a large patch stays interactive; the seam is still smooth, just
/// slightly less spread into the middle.
///
/// Either way the fill is blended in by the hole's own alpha, so a soft
/// brush edge stays soft. Returns a new buffer; [rgb] is left alone.
Uint8List cloneRegion(
  Uint8List rgb,
  int width,
  int height,
  Float32List alpha, {
  required int offsetX,
  required int offsetY,
  CloneFill fill = CloneFill.clone,
  double threshold = inpaintHoleThreshold,
  int iterations = 400,
}) {
  final bounds = maskBounds(alpha, width, height, threshold: threshold);
  if (bounds == null) {
    return rgb;
  }
  final out = Uint8List.fromList(rgb);
  int srcIndex(int x, int y) {
    final sx = (x + offsetX).clamp(0, width - 1);
    final sy = (y + offsetY).clamp(0, height - 1);
    return (sy * width + sx) * 3;
  }

  if (fill == CloneFill.clone) {
    for (var y = bounds.top; y <= bounds.bottom; y++) {
      for (var x = bounds.left; x <= bounds.right; x++) {
        final a = alpha[y * width + x];
        if (a < threshold) continue;
        final d = (y * width + x) * 3;
        final s = srcIndex(x, y);
        for (var c = 0; c < 3; c++) {
          out[d + c] = (rgb[d + c] + (rgb[s + c] - rgb[d + c]) * a).round();
        }
      }
    }
    return out;
  }

  // Heal: the working box is the hole's bounds plus a one-pixel ring.
  final bw = bounds.right - bounds.left + 3;
  final bh = bounds.bottom - bounds.top + 3;
  final region = Uint8List(bw * bh); // 0 outside, 1 hole, 2 boundary
  for (var y = 0; y < bh; y++) {
    for (var x = 0; x < bw; x++) {
      final ix = bounds.left + x - 1, iy = bounds.top + y - 1;
      if (ix >= 0 &&
          ix < width &&
          iy >= 0 &&
          iy < height &&
          alpha[iy * width + ix] >= threshold) {
        region[y * bw + x] = 1;
      }
    }
  }
  final v = Float32List(bw * bh * 3);
  final omega = <int>[];
  // The whole box, ring included: the hole touches its own bounds, so
  // the boundary cells sit on the ring and a loop that skipped the ring
  // would leave them at zero and the interior would relax to nothing.
  for (var y = 0; y < bh; y++) {
    for (var x = 0; x < bw; x++) {
      final i = y * bw + x;
      if (region[i] == 0) {
        if ((y > 0 && region[i - bw] == 1) ||
            (y < bh - 1 && region[i + bw] == 1) ||
            (x > 0 && region[i - 1] == 1) ||
            (x < bw - 1 && region[i + 1] == 1)) {
          region[i] = 2;
          final ix = bounds.left + x - 1, iy = bounds.top + y - 1;
          final d = (iy * width + ix) * 3;
          final s = srcIndex(ix, iy);
          for (var c = 0; c < 3; c++) {
            v[i * 3 + c] = (rgb[d + c] - rgb[s + c]).toDouble();
          }
        }
      } else if (region[i] == 1) {
        omega.add(i);
      }
    }
  }
  // Keep the solve near a hundred million cell updates at most.
  final steps = math.max(
    40,
    math.min(iterations, 100000000 ~/ math.max(omega.length, 1)),
  );
  const relax = 1.6;
  for (var it = 0; it < steps; it++) {
    for (final i in omega) {
      for (var c = 0; c < 3; c++) {
        final k = i * 3 + c;
        final sum =
            v[(i - bw) * 3 + c] +
            v[(i + bw) * 3 + c] +
            v[(i - 1) * 3 + c] +
            v[(i + 1) * 3 + c];
        v[k] = (1.0 - relax) * v[k] + relax * 0.25 * sum;
      }
    }
  }
  for (final i in omega) {
    final x = i % bw, y = i ~/ bw;
    final ix = bounds.left + x - 1, iy = bounds.top + y - 1;
    final a = alpha[iy * width + ix];
    final d = (iy * width + ix) * 3;
    final s = srcIndex(ix, iy);
    for (var c = 0; c < 3; c++) {
      final healed = (rgb[s + c] + v[i * 3 + c]).clamp(0.0, 255.0);
      out[d + c] = (rgb[d + c] + (healed - rgb[d + c]) * a).round();
    }
  }
  return out;
}

/// Lays a generative server's [patch] over [rgb] inside the hole — the
/// patch covers the frame rectangle ([left], [top], [patchWidth],
/// [patchHeight]) given as fractions of the frame, resampled to whatever
/// resolution this runs at, and blended in by the hole's own alpha so
/// only the painted area changes. Returns a new buffer.
Uint8List compositePatch(
  Uint8List rgb,
  int width,
  int height,
  Float32List alpha,
  img.Image patch, {
  required double left,
  required double top,
  required double patchWidth,
  required double patchHeight,
  double threshold = inpaintHoleThreshold,
}) {
  if (patchWidth <= 0 || patchHeight <= 0) {
    return rgb;
  }
  final out = Uint8List.fromList(rgb);
  final px = left * width, py = top * height;
  final pw = patchWidth * width, ph = patchHeight * height;
  final x0 = px.floor().clamp(0, width - 1);
  final y0 = py.floor().clamp(0, height - 1);
  final x1 = (px + pw).ceil().clamp(0, width);
  final y1 = (py + ph).ceil().clamp(0, height);
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final a = alpha[y * width + x];
      if (a < threshold) continue;
      final u = ((x + 0.5 - px) / pw * patch.width).floor().clamp(
        0,
        patch.width - 1,
      );
      final v = ((y + 0.5 - py) / ph * patch.height).floor().clamp(
        0,
        patch.height - 1,
      );
      final p = patch.getPixel(u, v);
      final d = (y * width + x) * 3;
      out[d] = (rgb[d] + (p.r - rgb[d]) * a).round();
      out[d + 1] = (rgb[d + 1] + (p.g - rgb[d + 1]) * a).round();
      out[d + 2] = (rgb[d + 2] + (p.b - rgb[d + 2]) * a).round();
    }
  }
  return out;
}
