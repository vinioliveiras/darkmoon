import 'dart:typed_data';

/// Rec.709 luma weights — matches how Meridian/ACR (and virtually every
/// display pipeline) weighs channels when deriving luminance from
/// gamma-encoded RGB, instead of the unweighted `(r+g+b)/3` average used
/// throughout this file's older call sites. Green carries far more
/// perceived brightness than blue, so an unweighted average both misjudges
/// which pixels are "dark" (shifting where tone/detail adjustments kick in)
/// and, when fed back into all three channels, nudges hue.
const double _lumaR = 0.2126;
const double _lumaG = 0.7152;
const double _lumaB = 0.0722;

/// Rec.709 luminance of a single 0-255 gamma-encoded RGB triple, returned
/// in the same 0-255 scale (not normalized).
double luminanceRgb(double r, double g, double b) =>
    _lumaR * r + _lumaG * g + _lumaB * b;

/// Fills [out] (size `rgb.length ~/ 3`) with the Rec.709 luminance of every
/// pixel in packed RGB [rgb] (3 values/pixel, 0-255 scale).
void extractLuminance(Float32List rgb, Float32List out) {
  final pixelCount = out.length;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    out[p] = luminanceRgb(rgb[i], rgb[i + 1], rgb[i + 2]);
  }
}

/// Adds [delta] (a single-channel, one-value-per-pixel buffer) equally to
/// all three channels of packed RGB [rgb] — used to push a luminance-only
/// adjustment (Texture, Clarity, Sharpen) back into RGB without touching
/// chroma, since adding the same delta to R/G/B shifts brightness without
/// changing the R-G/B-G chroma differences.
void applyLuminanceDelta(Float32List rgb, Float32List delta) {
  final pixelCount = delta.length;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final d = delta[p];
    rgb[i] += d;
    rgb[i + 1] += d;
    rgb[i + 2] += d;
  }
}
