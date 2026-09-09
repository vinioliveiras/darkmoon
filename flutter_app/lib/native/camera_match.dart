import 'dart:math' as math;
import 'dart:typed_data';

import '../render/calibration.dart';
import '../render/color_profile.dart' show colorProfileTonePoints;
import '../render/color_space.dart';

import 'package:image/image.dart' as img;

/// Nudges [rgbBytes] (packed, row-major, 3 bytes/pixel — same layout as
/// [RawImage.rgbBytes]) toward the color/tone of [embeddedJpegBytes], the
/// camera's own embedded preview JPEG for the same shot (see
/// `extractRawThumbnailJpeg`). Mutates and returns [rgbBytes] in place, or
/// returns it unchanged if [embeddedJpegBytes] is null, fails to decode,
/// or looks like a mismatched/differently-oriented crop (aspect ratio
/// guard below) — never throws.
///
/// This is a deliberately simplified stand-in for what a full "camera
/// match" does (see Vitrine's per-image 3x3-matrix + tone-curve + 3D-LUT
/// fit, `cameraMatch.cjs` in github.com/Redrum624/Vitrine): a single
/// clamped gain per channel, derived from comparing the two images' mean
/// color rather than a real geometric/tonal fit. LibRaw's demosaic and the
/// camera's own JPEG aren't guaranteed to be pixel-aligned (different
/// crop, orientation baked in differently, etc.), so per-pixel or LUT
/// fitting would need real alignment first — a global mean-ratio nudge
/// needs no alignment and degrades gracefully (worst case, ~no visible
/// change) if the two don't quite match, instead of a full LUT fit's
/// worst case (a visibly wrong local color shift).
Uint8List applyCameraMatch(
  Uint8List rgbBytes,
  int width,
  int height,
  Uint8List? embeddedJpegBytes,
) {
  if (embeddedJpegBytes == null) {
    return rgbBytes;
  }
  img.Image? jpeg;
  try {
    jpeg = img.decodeJpg(embeddedJpegBytes);
  } on Exception {
    // decodeJpg throws (rather than returning null) on malformed bytes —
    // this path already always has real, LibRaw-extracted JPEG bytes, but
    // "no embedded thumbnail" must never be able to break the main RAW
    // decode it's piggybacking on, so treat any decode failure as
    // no-adjustment rather than letting it propagate.
    jpeg = null;
  }
  if (jpeg == null || jpeg.width == 0 || jpeg.height == 0) {
    return rgbBytes;
  }

  final rawAspect = width / height;
  final jpegAspect = jpeg.width / jpeg.height;
  // Guard against comparing a portrait-oriented thumbnail against a
  // landscape-oriented decode (or vice versa) — the means of two
  // differently-rotated crops of a non-symmetric scene aren't comparable,
  // and applying a "gain" derived from them could shift color in a
  // visibly wrong direction rather than just doing nothing.
  final aspectRatio = rawAspect / jpegAspect;
  if (aspectRatio < 0.8 || aspectRatio > 1.25) {
    return rgbBytes;
  }

  final rawMeans = _meanRgb(rgbBytes);
  final jpegMeans = _meanRgb(jpeg.getBytes(order: img.ChannelOrder.rgb));

  // Clamped to a modest range: this is a nudge toward the camera's own
  // rendering, not a full replacement for it — a wide gain range would
  // let a bad (misaligned/atypical) comparison swing color too far.
  double gain(double from, double to) =>
      (to / (from < 1 ? 1 : from)).clamp(0.85, 1.2);
  final gains = (
    r: gain(rawMeans.$1, jpegMeans.$1),
    g: gain(rawMeans.$2, jpegMeans.$2),
    b: gain(rawMeans.$3, jpegMeans.$3),
  );

  for (var i = 0; i < rgbBytes.length; i += 3) {
    rgbBytes[i] = (rgbBytes[i] * gains.r).clamp(0, 255).round();
    rgbBytes[i + 1] = (rgbBytes[i + 1] * gains.g).clamp(0, 255).round();
    rgbBytes[i + 2] = (rgbBytes[i + 2] * gains.b).clamp(0, 255).round();
  }
  return rgbBytes;
}

/// Mean of each channel across a packed RGB buffer (any layout, since only
/// the running sums per channel-position matter, not width/height).
(double, double, double) _meanRgb(Uint8List rgbBytes) {
  var sumR = 0, sumG = 0, sumB = 0;
  final pixelCount = rgbBytes.length ~/ 3;
  if (pixelCount == 0) {
    return (0, 0, 0);
  }
  for (var i = 0; i < rgbBytes.length; i += 3) {
    sumR += rgbBytes[i];
    sumG += rgbBytes[i + 1];
    sumB += rgbBytes[i + 2];
  }
  return (sumR / pixelCount, sumG / pixelCount, sumB / pixelCount);
}

/// Mean luma of an 8-bit RGB buffer, normalised to 0-1 and left in the
/// encoding the bytes are already in — **not** linearised. See
/// [cameraExposureOffsetStops] for why that is the whole point.
double _meanEncodedLuma(Uint8List rgb) {
  if (rgb.length < 3) {
    return 0;
  }
  var sum = 0.0;
  for (var i = 0; i + 2 < rgb.length; i += 3) {
    sum += 0.2126 * rgb[i] + 0.7152 * rgb[i + 1] + 0.0722 * rgb[i + 2];
  }
  return sum / (rgb.length / 3) / 255.0;
}

/// How many stops [rgbBytes] sits away from the brightness of
/// [embeddedJpegBytes], the camera's own preview of the same shot.
///
/// Positive means the decode is darker than the camera's rendering and
/// wants opening up. Null when there is nothing trustworthy to compare —
/// no preview, a preview of a different shape, or a frame too dark for a
/// ratio to mean anything.
///
/// **Luminance only, and deliberately.** [applyCameraMatch] above does the
/// same comparison per channel and is not used, because against a
/// camera's film-simulation JPEG the per-channel gains introduced a
/// yellow/green cast — it was matching a colour rendering, not correcting
/// one. Brightness carries none of that: how bright the camera decided the
/// scene should be is a judgement worth inheriting, and it says nothing
/// about hue.
///
/// **The means are taken in the encoding the pixels arrive in, not in
/// linear light** — and that is not the obvious choice, so: this number
/// does not stay a physical quantity. It is handed to the Exposure slider
/// (via [RenderParams.fromValues]), and `_applyExposure` multiplies the
/// *gamma-encoded* buffer by `2^(units / calExposureUnitsPerStop)`. A
/// gamma-space multiply is not a linear-light exposure change: measured
/// on a flat patch, six slider units — half a stop by that constant's
/// arithmetic, and half a stop of gamma-space gain — moves the linear
/// luminance a full stop.
///
/// So a correction measured in linear light and spent through this knob
/// lands about twice as strong as it should. On a Fujifilm X-T5 frame
/// (2026-09-09) the linear measurement asked for +0.238 stops where the
/// decode was already within 3% of the camera's own rendering; applied,
/// it pushed the mean from 87.6 to 103.0 and clipped 2.9% of the frame.
/// That is the highlights blowing out.
///
/// Measuring in the same space the correction is spent in makes the two
/// cancel: multiplying our buffer by `preview / decoded` puts its mean
/// exactly on the camera's, by construction. This was previously
/// linearised, with a comment arguing that exposure is a multiplication
/// in linear light — true of exposure in general, and not true of this
/// pipeline's Exposure stage.
double? cameraExposureOffsetStops(
  Uint8List rgbBytes,
  int width,
  int height,
  Uint8List? embeddedJpegBytes, {
  double limitStops = calCameraExposureLimitStops,
  double lumaFloor = calCameraExposureLumaFloor,
}) {
  if (embeddedJpegBytes == null || width <= 0 || height <= 0) {
    return null;
  }
  img.Image? jpeg;
  try {
    jpeg = img.decodeJpg(embeddedJpegBytes);
  } on Exception {
    jpeg = null;
  }
  if (jpeg == null || jpeg.width == 0 || jpeg.height == 0) {
    return null;
  }

  // Same guard as applyCameraMatch, for the same reason: the means of two
  // differently-oriented crops of a scene are not comparable.
  final aspect = (width / height) / (jpeg.width / jpeg.height);
  if (aspect < 0.8 || aspect > 1.25) {
    return null;
  }

  final decoded = _meanEncodedLuma(rgbBytes);
  final preview = _meanEncodedLuma(jpeg.getBytes(order: img.ChannelOrder.rgb));
  if (decoded < lumaFloor || preview < lumaFloor) {
    return null;
  }
  final stops = math.log(preview / decoded) / math.ln2;
  return stops.clamp(-limitStops, limitStops);
}


// ═══════════════════════════════════════════════════════════════════════
//  Camera tone match
// ═══════════════════════════════════════════════════════════════════════

/// How many bins the perceptual-luma histograms below are built over.
/// Finer than the 33 points the fit is sampled at, so the percentile
/// lookup is not itself the limiting resolution.
const int _toneHistogramBins = 1024;

/// Roughly how many pixels each histogram samples.
///
/// A histogram is a shape, and a few hundred thousand pixels fix that
/// shape as well as forty million do — a full-sensor frame is 40 MP and
/// walking all of it here would cost more than the fit is worth. The
/// stride is computed per image so both sides of the comparison are
/// sampled about equally densely.
const int _toneSampleTarget = 400000;

/// Perceptual-luma histogram of a packed RGB buffer, sampled with a
/// stride (see [_toneSampleTarget]).
Float64List _perceptualHistogram(Uint8List rgb) {
  final pixels = rgb.length ~/ 3;
  final stride = pixels <= _toneSampleTarget
      ? 1
      : (pixels / _toneSampleTarget).ceil();
  final hist = Float64List(_toneHistogramBins);
  for (var px = 0; px < pixels; px += stride) {
    final i = px * 3;
    final linear =
        0.2126 * srgbToLinear(rgb[i] / 255.0) +
        0.7152 * srgbToLinear(rgb[i + 1] / 255.0) +
        0.0722 * srgbToLinear(rgb[i + 2] / 255.0);
    final bin = (perceptualEncode(linear) * (_toneHistogramBins - 1))
        .round()
        .clamp(0, _toneHistogramBins - 1);
    hist[bin]++;
  }
  return hist;
}

/// [hist] as a normalised cumulative distribution.
Float64List _cdf(Float64List hist) {
  final cdf = Float64List(_toneHistogramBins);
  var acc = 0.0;
  for (var i = 0; i < _toneHistogramBins; i++) {
    acc += hist[i];
    cdf[i] = acc;
  }
  if (acc <= 0) {
    return cdf;
  }
  for (var i = 0; i < _toneHistogramBins; i++) {
    cdf[i] /= acc;
  }
  return cdf;
}

/// The identity tone curve — [colorProfileTonePoints] points, `tone[i]`
/// the output for input `i / (N - 1)`.
List<double> _identityTone() => [
  for (var i = 0; i < colorProfileTonePoints; i++)
    i / (colorProfileTonePoints - 1),
];

/// A [ColorProfile.tone] curve that maps [rgbBytes]'s tonality onto
/// [embeddedJpegBytes]'s — the camera's own rendering of the same shot.
///
/// Where [cameraExposureOffsetStops] answers "how much brighter", this
/// answers "brighter *where*", and it subsumes the other: a curve that
/// carries the camera's whole tonality carries its mean along with it.
/// Both are measured from the same pair, so a photo that has one has the
/// other; the renderer must spend exactly one of them, never both.
///
/// **Histogram specification, not a fit.** For each of the 33 control
/// points, the input perceptual luma is converted to a percentile of this
/// decode, and the output is the luma at that same percentile of the
/// camera's frame. That needs no geometric alignment between the two —
/// which matters, because LibRaw's demosaic of the full sensor and the
/// camera's JPEG are not the same crop and never will be. The result is
/// forced monotone, so it can only ever redistribute tonality, never
/// invert it.
///
/// **Luminance only**, and for the same reason [cameraExposureOffsetStops]
/// is: the curve rides the profile's tone slot, which remaps luminance and
/// leaves chroma alone. Matching the camera's *colour* per channel was
/// tried and reverted — against a film-simulation JPEG it introduced a
/// yellow/green cast (see [applyCameraMatch]). How the camera distributed
/// its tones is a judgement worth inheriting; its colour science is not.
///
/// Null under exactly the conditions [cameraExposureOffsetStops] refuses,
/// so the two are always present or absent together.
///
/// Measured 2026-09-09 across three X-T5 frames: mean absolute error over
/// the 1st-99th percentiles falls from 12.5 levels (the hand-tuned
/// [calBaseContrast] S-curve) to 0.6.
List<double>? cameraToneCurve(
  Uint8List rgbBytes,
  int width,
  int height,
  Uint8List? embeddedJpegBytes, {
  double lumaFloor = calCameraExposureLumaFloor,
}) {
  if (embeddedJpegBytes == null || width <= 0 || height <= 0) {
    return null;
  }
  img.Image? jpeg;
  try {
    jpeg = img.decodeJpg(embeddedJpegBytes);
  } on Exception {
    jpeg = null;
  }
  if (jpeg == null || jpeg.width == 0 || jpeg.height == 0) {
    return null;
  }
  // Same guard, same reason, as the offset's: the tonality of two
  // differently-oriented crops of a scene are not each other's target.
  final aspect = (width / height) / (jpeg.width / jpeg.height);
  if (aspect < 0.8 || aspect > 1.25) {
    return null;
  }
  final cameraRgb = jpeg.getBytes(order: img.ChannelOrder.rgb);
  if (_meanEncodedLuma(rgbBytes) < lumaFloor ||
      _meanEncodedLuma(cameraRgb) < lumaFloor) {
    return null;
  }

  final ourCdf = _cdf(_perceptualHistogram(rgbBytes));
  final cameraCdf = _cdf(_perceptualHistogram(cameraRgb));
  final tone = <double>[];
  var cameraBin = 0;
  for (var k = 0; k < colorProfileTonePoints; k++) {
    final input = k / (colorProfileTonePoints - 1);
    final sourceBin = (input * (_toneHistogramBins - 1))
        .round()
        .clamp(0, _toneHistogramBins - 1);
    final target = ourCdf[sourceBin];
    // Monotone in k, so the scan never rewinds — this is one pass over
    // the camera CDF across the whole loop, not 33.
    while (cameraBin < _toneHistogramBins - 1 && cameraCdf[cameraBin] < target) {
      cameraBin++;
    }
    var output = cameraBin / (_toneHistogramBins - 1);
    if (tone.isNotEmpty && output < tone.last) {
      output = tone.last;
    }
    tone.add(output.clamp(0.0, 1.0));
  }
  // An all-flat curve means one of the two frames had no tonal range to
  // speak of; identity is the honest answer, and the renderer skips it.
  return tone.last <= tone.first ? _identityTone() : tone;
}
