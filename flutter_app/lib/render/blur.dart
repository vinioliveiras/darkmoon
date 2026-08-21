import 'dart:math' as math;
import 'dart:typed_data';

/// Single-channel blur/filter helpers used by local contrast (Texture,
/// Clarity) and Dehaze. All operate on a flat, row-major, single-channel
/// [Float32List] of size `width * height`, with clamp-to-edge boundaries
/// (the Python app's scipy filters use 'reflect'/'nearest' — close enough
/// visually for a photo preview that this doesn't need to match exactly).

Float32List _boxBlurHorizontal(
  Float32List src,
  int width,
  int height,
  int radius,
) {
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

Float32List _boxBlurVertical(
  Float32List src,
  int width,
  int height,
  int radius,
) {
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
Float32List boxBlurMean(
  Float32List channel,
  int width,
  int height,
  int radius,
) {
  if (radius <= 0) {
    return Float32List.fromList(channel);
  }
  return _boxBlurVertical(
    _boxBlurHorizontal(channel, width, height, radius),
    width,
    height,
    radius,
  );
}

/// Box radii for a 3-pass box-blur approximation of a Gaussian with the
/// given [sigma] — the standard "fast Gaussian via repeated box blur"
/// technique (Kovesi / Getreuer), since a true Gaussian kernel would cost
/// O(sigma) per pixel and Clarity's sigma (25) is too large for that to
/// stay fast at preview resolutions. Public so the GPU render path
/// (`lib/render/gpu/`) can precompute the same radii on CPU and pass them
/// as shader uniforms, rather than reimplementing this math in GLSL.
List<int> boxRadiiForGauss(double sigma, int passes) {
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
      (12 * sigma * sigma - passes * wl * wl - 4 * passes * wl - 3 * passes) /
      (-4 * wl - 4);
  final m = mIdeal.round();
  return [for (var i = 0; i < passes; i++) ((i < m ? wl : wu) - 1) ~/ 2];
}

/// Approximate Gaussian blur (3-pass box blur) matching scipy's
/// `gaussian_filter(..., sigma=sigma)` closely enough for a tone-mapping
/// preview effect.
Float32List gaussianBlurChannel(
  Float32List channel,
  int width,
  int height,
  double sigma,
) {
  if (sigma <= 0) {
    return Float32List.fromList(channel);
  }
  var result = channel;
  for (final radius in boxRadiiForGauss(sigma, 3)) {
    result = boxBlurMean(result, width, height, radius);
  }
  return result;
}

Float32List _minFilterHorizontal(
  Float32List src,
  int width,
  int height,
  int radius,
) {
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

Float32List _minFilterVertical(
  Float32List src,
  int width,
  int height,
  int radius,
) {
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
  return _minFilterVertical(
    _minFilterHorizontal(channel, width, height, radius),
    width,
    height,
    radius,
  );
}

/// Blends [channel] with a Gaussian-blurred ([sigma]) version of itself,
/// weighting each pixel's contribution from the blur by how far its local
/// high-frequency energy stands out above the *surrounding* region's own
/// typical high-frequency energy — a self-calibrating (Wiener-style soft
/// threshold) estimate of that region's noise floor, rather than a single
/// fixed magnitude cutoff picked by eye against one test photo. A pixel
/// whose residual is about the size of its neighborhood's typical residual
/// reads as noise and gets mostly smoothed; one well above it reads as a
/// real edge/detail and mostly survives — and because the "typical
/// residual" is measured locally, a photo's noisier shadows and cleaner
/// highlights each get an amount of smoothing suited to what's actually
/// there, and a low-ISO shot doesn't get over-smoothed by a threshold
/// tuned against a noisier one.
///
/// [strength] (0..1) is the overall blend amount, same convention as every
/// other adjustment; [noiseRadius] sets how wide a neighborhood the local
/// noise floor is estimated over.
Float32List adaptiveDenoiseChannel(
  Float32List channel,
  int width,
  int height,
  double sigma,
  double strength, {
  int noiseRadius = 6,
}) {
  if (strength <= 0) {
    return Float32List.fromList(channel);
  }
  final blurred = gaussianBlurChannel(channel, width, height, sigma);
  final n = channel.length;
  final residualSq = Float32List(n);
  for (var i = 0; i < n; i++) {
    final r = channel[i] - blurred[i];
    residualSq[i] = r * r;
  }
  final localNoiseVar = localVarianceFromResidualSq(
    residualSq,
    width,
    height,
    noiseRadius,
  );
  final out = Float32List(n);
  for (var i = 0; i < n; i++) {
    final r = channel[i] - blurred[i];
    final rSq = r * r;
    final edgeWeight = rSq / (rSq + localNoiseVar[i] + 1.0);
    final denoised = blurred[i] + r * edgeWeight;
    out[i] = channel[i] + (denoised - channel[i]) * strength;
  }
  return out;
}

/// Computes a per-pixel local variance estimate from a precomputed
/// squared-residual buffer. This is the same local-variance estimator used by
/// [adaptiveDenoiseChannel], extracted for reuse by Texture/Clarity/Sharpen.
///
/// [residualSq] is a single-channel [Float32List] of size `width * height`
/// containing (pixel - blurred_pixel)^2. The function returns a buffer of the
/// same size where each pixel is the mean of [residualSq] over a
/// (2*[noiseRadius]+1) x (2*[noiseRadius]+1) box window around it.
Float32List localVarianceFromResidualSq(
  Float32List residualSq,
  int width,
  int height,
  int noiseRadius,
) {
  return boxBlurMean(residualSq, width, height, noiseRadius);
}

/// Area-average downsample of a single-channel buffer by an integer
/// [factor] in each dimension (e.g. `factor: 4` means 1/16th the pixels).
/// [width] doesn't need to be an exact multiple of [factor] — the last
/// column of blocks just averages over however many source columns remain.
///
/// [rowOffset] is [channel]'s row 0's *absolute* row index in some larger
/// image this buffer is a horizontal slice of (0 if it's the whole
/// image). Block boundaries are computed in that absolute coordinate
/// space, not relative to this buffer's own row 0 — so a slice starting
/// mid-image still downsamples using the exact same block grid the whole
/// image would have used, rather than restarting a fresh grid at
/// wherever the slice happens to begin. This is what makes it safe to
/// downsample an image split into independent horizontal bands and get
/// the same result as downsampling it whole: without this, two adjacent
/// slices' block grids would disagree about where a block starts, and
/// every row in both bands (not just near the seam) could land in a
/// differently-averaged block than the whole-image computation would
/// have put it in.
({Float32List channel, int width, int height}) downsampleChannel(
  Float32List channel,
  int width,
  int height,
  int factor, {
  int rowOffset = 0,
}) {
  final outWidth = (width / factor).ceil();
  final firstBlock = rowOffset ~/ factor;
  final lastBlock = (rowOffset + height - 1) ~/ factor;
  final outHeight = lastBlock - firstBlock + 1;
  final out = Float32List(outWidth * outHeight);
  for (var ob = 0; ob < outHeight; ob++) {
    final blockAbsoluteY0 = (firstBlock + ob) * factor;
    final y0 = math.max(blockAbsoluteY0 - rowOffset, 0);
    final y1 = math.min(blockAbsoluteY0 + factor - rowOffset, height);
    for (var ox = 0; ox < outWidth; ox++) {
      final x0 = ox * factor;
      final x1 = math.min(x0 + factor, width);
      var sum = 0.0;
      for (var y = y0; y < y1; y++) {
        final rowStart = y * width;
        for (var x = x0; x < x1; x++) {
          sum += channel[rowStart + x];
        }
      }
      out[ob * outWidth + ox] = sum / ((y1 - y0) * (x1 - x0));
    }
  }
  return (channel: out, width: outWidth, height: outHeight);
}

/// Nearest-neighbor upsample of a single-channel buffer from `srcWidth x
/// srcHeight` back to `dstWidth x dstHeight`, for an exact integer
/// [factor] — the cheap inverse of [downsampleChannel]: a single array
/// read and no interpolation math per destination pixel. Safe for a
/// subtle, low-strength effect (visible block edges would need both a
/// hard color transition *and* strength high enough to notice blockiness,
/// neither of which apply to baseline chroma smoothing).
///
/// [rowOffset] must be the exact same value passed to the
/// [downsampleChannel] call that produced [src], so both agree on which
/// absolute row each of [src]'s rows represents.
Float32List upsampleChannelNearest(
  Float32List src,
  int srcWidth,
  int srcHeight,
  int factor,
  int dstWidth,
  int dstHeight, {
  int rowOffset = 0,
}) {
  final firstBlock = rowOffset ~/ factor;
  final out = Float32List(dstWidth * dstHeight);
  for (var y = 0; y < dstHeight; y++) {
    final sy = ((rowOffset + y) ~/ factor - firstBlock).clamp(0, srcHeight - 1);
    final srcRow = sy * srcWidth;
    final dstRow = y * dstWidth;
    for (var x = 0; x < dstWidth; x++) {
      final sx = (x ~/ factor).clamp(0, srcWidth - 1);
      out[dstRow + x] = src[srcRow + sx];
    }
  }
  return out;
}
