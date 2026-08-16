import 'dart:math' as math;
import 'dart:typed_data';

/// Single-channel blur/filter helpers used by local contrast (Texture,
/// Clarity) and Dehaze. All operate on a flat, row-major, single-channel
/// [Float32List] of size `width * height`, with clamp-to-edge boundaries
/// (the Python app's scipy filters use 'reflect'/'nearest' — close enough
/// visually for a photo preview that this doesn't need to match exactly).

Float32List _boxBlurHorizontal(Float32List src, int width, int height, int radius) {
  final out = Float32List(src.length);
  final windowSize = radius * 2 + 1;
  for (var y = 0; y < height; y++) {
    final rowStart = y * width;
    var sum = 0.0;
    for (var k = -radius; k <= radius; k++) {
      sum += src[rowStart + k.clamp(0, width - 1)];
    }
    out[rowStart] = sum / windowSize;
    for (var x = 1; x < width; x++) {
      sum += src[rowStart + (x + radius).clamp(0, width - 1)];
      sum -= src[rowStart + (x - radius - 1).clamp(0, width - 1)];
      out[rowStart + x] = sum / windowSize;
    }
  }
  return out;
}

Float32List _boxBlurVertical(Float32List src, int width, int height, int radius) {
  final out = Float32List(src.length);
  final windowSize = radius * 2 + 1;
  for (var x = 0; x < width; x++) {
    var sum = 0.0;
    for (var k = -radius; k <= radius; k++) {
      sum += src[k.clamp(0, height - 1) * width + x];
    }
    out[x] = sum / windowSize;
    for (var y = 1; y < height; y++) {
      sum += src[(y + radius).clamp(0, height - 1) * width + x];
      sum -= src[(y - radius - 1).clamp(0, height - 1) * width + x];
      out[y * width + x] = sum / windowSize;
    }
  }
  return out;
}

/// Exact box (mean) blur with the given [radius] (window size `2*radius+1`),
/// via a separable sliding-window sum — O(width*height) regardless of
/// radius.
Float32List boxBlurMean(Float32List channel, int width, int height, int radius) {
  if (radius <= 0) {
    return Float32List.fromList(channel);
  }
  return _boxBlurVertical(_boxBlurHorizontal(channel, width, height, radius), width, height, radius);
}

/// Box radii for a 3-pass box-blur approximation of a Gaussian with the
/// given [sigma] — the standard "fast Gaussian via repeated box blur"
/// technique (Kovesi / Getreuer), since a true Gaussian kernel would cost
/// O(sigma) per pixel and Clarity's sigma (25) is too large for that to
/// stay fast at preview resolutions.
List<int> _boxRadiiForGauss(double sigma, int passes) {
  if (sigma <= 0) {
    return List.filled(passes, 0);
  }
  final wIdeal = math.sqrt((12 * sigma * sigma / passes) + 1);
  var wl = wIdeal.floor();
  if (wl % 2 == 0) {
    wl -= 1;
  }
  final wu = wl + 2;
  final mIdeal =
      (12 * sigma * sigma - passes * wl * wl - 4 * passes * wl - 3 * passes) / (-4 * wl - 4);
  final m = mIdeal.round();
  return [for (var i = 0; i < passes; i++) ((i < m ? wl : wu) - 1) ~/ 2];
}

/// Approximate Gaussian blur (3-pass box blur) matching scipy's
/// `gaussian_filter(..., sigma=sigma)` closely enough for a tone-mapping
/// preview effect.
Float32List gaussianBlurChannel(Float32List channel, int width, int height, double sigma) {
  if (sigma <= 0) {
    return Float32List.fromList(channel);
  }
  var result = channel;
  for (final radius in _boxRadiiForGauss(sigma, 3)) {
    result = boxBlurMean(result, width, height, radius);
  }
  return result;
}

Float32List _minFilterHorizontal(Float32List src, int width, int height, int radius) {
  final out = Float32List(src.length);
  for (var y = 0; y < height; y++) {
    final rowStart = y * width;
    for (var x = 0; x < width; x++) {
      final lo = (x - radius).clamp(0, width - 1);
      final hi = (x + radius).clamp(0, width - 1);
      var m = src[rowStart + lo];
      for (var xi = lo + 1; xi <= hi; xi++) {
        final v = src[rowStart + xi];
        if (v < m) {
          m = v;
        }
      }
      out[rowStart + x] = m;
    }
  }
  return out;
}

Float32List _minFilterVertical(Float32List src, int width, int height, int radius) {
  final out = Float32List(src.length);
  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      final lo = (y - radius).clamp(0, height - 1);
      final hi = (y + radius).clamp(0, height - 1);
      var m = src[lo * width + x];
      for (var yi = lo + 1; yi <= hi; yi++) {
        final v = src[yi * width + x];
        if (v < m) {
          m = v;
        }
      }
      out[y * width + x] = m;
    }
  }
  return out;
}

/// Sliding-window minimum ("erosion") over a `size x size` square window —
/// matches scipy's `minimum_filter(..., size=size)`. Separable into a
/// horizontal then vertical 1D pass since min is associative.
Float32List minFilter(Float32List channel, int width, int height, int size) {
  final radius = (size - 1) ~/ 2;
  if (radius <= 0) {
    return Float32List.fromList(channel);
  }
  return _minFilterVertical(_minFilterHorizontal(channel, width, height, radius), width, height, radius);
}
