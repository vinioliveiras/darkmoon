import 'dart:math' as math;
import 'dart:typed_data';

import '../render/calibration.dart';
import '../render/color_profile.dart'
    show colorProfileBins, colorProfileTonePoints;
import '../render/hsl.dart';
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

/// Everything both measurements need from one image, gathered in a single
/// strided pass.
///
/// One pass rather than three, and a stride rather than every pixel,
/// because this runs on the path that opens a photo. Walking a 13 MP
/// embedded JPEG and a 6 MP preview end to end, twice each, was 2.1s of a
/// 2.5s warm open (measured 2026-09-09) — most of it not even here but in
/// decoding the same JPEG twice, which [measureCameraMatch] now does once.
class _ImageStats {
  const _ImageStats(
    this.meanEncodedLuma,
    this.meanLinearLuma,
    this.perceptualHistogram,
  );

  /// Mean luma, normalised to 0-1, in the encoding the bytes are already
  /// in. Only the "is this frame dark enough to be untrustworthy" floor
  /// reads it, in the units the floor was set in.
  final double meanEncodedLuma;

  /// Mean luma in linear light, 0-1 — what an exposure ratio is a ratio
  /// of. See [cameraExposureOffsetStops].
  final double meanLinearLuma;

  /// Perceptual-luma histogram, [_toneHistogramBins] wide over 0-1.
  final Float64List perceptualHistogram;
}

/// Roughly how many pixels [_statsOf] samples.
///
/// A mean and a histogram are both shapes, and a few hundred thousand
/// pixels fix them as well as forty million do.
const int _statsSampleTarget = 400000;

_ImageStats _statsOf(Uint8List rgb) {
  final pixels = rgb.length ~/ 3;
  if (pixels == 0) {
    return _ImageStats(0, 0, Float64List(_toneHistogramBins));
  }
  final stride = pixels <= _statsSampleTarget
      ? 1
      : (pixels / _statsSampleTarget).ceil();
  final hist = Float64List(_toneHistogramBins);
  var sum = 0.0;
  var linearSum = 0.0;
  var counted = 0;
  for (var px = 0; px < pixels; px += stride) {
    final i = px * 3;
    final r = rgb[i];
    final g = rgb[i + 1];
    final b = rgb[i + 2];
    sum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final linear =
        0.2126 * srgbToLinear(r / 255.0) +
        0.7152 * srgbToLinear(g / 255.0) +
        0.0722 * srgbToLinear(b / 255.0);
    linearSum += linear;
    final bin = (perceptualEncode(linear) * (_toneHistogramBins - 1))
        .round()
        .clamp(0, _toneHistogramBins - 1);
    hist[bin]++;
    counted++;
  }
  return _ImageStats(sum / counted / 255.0, linearSum / counted, hist);
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
/// **Measured in linear light, in the space the correction is spent in.**
/// The answer goes to the Exposure slider (via [RenderParams.fromValues]),
/// and since 2026-09-10 `applyExposureAndWhiteBalance` multiplies the
/// *linear* light by `2^stops` — so a ratio of linear means, spent as
/// stops, puts our mean exactly on the camera's, by construction.
///
/// The space matters, and this file has been on both sides of it. Until
/// 2026-09-10 the Exposure stage multiplied the gamma-encoded buffer, and
/// a linear measurement spent through it landed about twice as strong: on
/// a Fujifilm X-T5 frame (2026-09-09) it asked for +0.238 stops where the
/// decode was within 3% of the camera's rendering, pushed the mean from
/// 87.6 to 103.0 and clipped 2.9% of the frame. The fix then was to
/// measure in gamma space too, so the two cancelled. Now that the stage
/// is linear, the measurement is linear again — for the same reason
/// (same space as the spend), not the opposite one.
double? cameraExposureOffsetStops(
  Uint8List rgbBytes,
  int width,
  int height,
  Uint8List? embeddedJpegBytes, {
  double limitStops = calCameraExposureLimitStops,
  double lumaFloor = calCameraExposureLumaFloor,
  EmbeddedPreview? preview,
}) {
  if (width <= 0 || height <= 0) {
    return null;
  }
  final jpeg = (preview ?? EmbeddedPreview.decode(embeddedJpegBytes))?.image;
  if (jpeg == null) {
    return null;
  }

  // Same guard as applyCameraMatch, for the same reason: the means of two
  // differently-oriented crops of a scene are not comparable.
  final aspect = (width / height) / (jpeg.width / jpeg.height);
  if (aspect < 0.8 || aspect > 1.25) {
    return null;
  }

  return _offsetFrom(
    _statsOf(rgbBytes),
    _statsOf(jpeg.getBytes(order: img.ChannelOrder.rgb)),
    limitStops: limitStops,
    lumaFloor: lumaFloor,
  );
}

/// The offset, from statistics already gathered.
double? _offsetFrom(
  _ImageStats ours,
  _ImageStats camera, {
  required double limitStops,
  required double lumaFloor,
}) {
  if (ours.meanEncodedLuma < lumaFloor || camera.meanEncodedLuma < lumaFloor) {
    return null;
  }
  final stops =
      math.log(camera.meanLinearLuma / ours.meanLinearLuma) / math.ln2;
  return stops.clamp(-limitStops, limitStops);
}

// ═══════════════════════════════════════════════════════════════════════
//  Camera tone match
// ═══════════════════════════════════════════════════════════════════════

/// How many bins the perceptual-luma histograms below are built over.
/// Finer than the 33 points the fit is sampled at, so the percentile
/// lookup is not itself the limiting resolution.
const int _toneHistogramBins = 1024;

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
  return _toneFrom(
    _statsOf(rgbBytes),
    _statsOf(jpeg.getBytes(order: img.ChannelOrder.rgb)),
    lumaFloor: lumaFloor,
  );
}

/// The curve, from statistics already gathered.
List<double>? _toneFrom(
  _ImageStats ours,
  _ImageStats camera, {
  required double lumaFloor,
}) {
  if (ours.meanEncodedLuma < lumaFloor || camera.meanEncodedLuma < lumaFloor) {
    return null;
  }
  final ourCdf = _cdf(ours.perceptualHistogram);
  final cameraCdf = _cdf(camera.perceptualHistogram);
  final tone = <double>[];
  var cameraBin = 0;
  for (var k = 0; k < colorProfileTonePoints; k++) {
    final input = k / (colorProfileTonePoints - 1);
    final sourceBin = (input * (_toneHistogramBins - 1)).round().clamp(
      0,
      _toneHistogramBins - 1,
    );
    final target = ourCdf[sourceBin];
    // Monotone in k, so the scan never rewinds — this is one pass over
    // the camera CDF across the whole loop, not 33.
    while (cameraBin < _toneHistogramBins - 1 &&
        cameraCdf[cameraBin] < target) {
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

/// Both measurements from one decode of [embeddedJpegBytes] and one pass
/// over each buffer — the form everything in the app actually uses.
///
/// The two public functions above are the same measurements taken
/// separately, kept because each is meaningful on its own and each is
/// tested on its own. Production never calls them: taken separately they
/// decode the camera's JPEG twice and walk both buffers twice, which on a
/// 13 MP embedded preview was 2.1 seconds of a 2.5-second warm open
/// (measured 2026-09-09, and the reason this exists).
CameraMatch measureCameraMatch(
  Uint8List rgbBytes,
  int width,
  int height,
  Uint8List? embeddedJpegBytes, {
  double limitStops = calCameraExposureLimitStops,
  double lumaFloor = calCameraExposureLumaFloor,
  EmbeddedPreview? preview,
}) {
  if (width <= 0 || height <= 0) {
    return CameraMatch.none;
  }
  final jpeg = (preview ?? EmbeddedPreview.decode(embeddedJpegBytes))?.image;
  if (jpeg == null) {
    return CameraMatch.none;
  }
  final aspect = (width / height) / (jpeg.width / jpeg.height);
  if (aspect < 0.8 || aspect > 1.25) {
    return CameraMatch.none;
  }
  final cameraRgb = jpeg.getBytes(order: img.ChannelOrder.rgb);
  final ours = _statsOf(rgbBytes);
  final camera = _statsOf(cameraRgb);
  final tone = _toneFrom(ours, camera, lumaFloor: lumaFloor);
  return CameraMatch(
    stops: _offsetFrom(
      ours,
      camera,
      limitStops: limitStops,
      lumaFloor: lumaFloor,
    ),
    tone: tone,
    color: cameraColorFit(
      rgbBytes,
      width,
      height,
      cameraRgb,
      jpeg.width,
      jpeg.height,
      tone: tone,
    ),
  );
}

// ---------------------------------------------------------------------------
//  Camera colour match
// ---------------------------------------------------------------------------

/// The per-hue colour rendering the camera applied and the decode did
/// not: what a [ColorProfile]'s `hueShift`/`satMul`/`lumMul` slots carry,
/// one entry per [colorProfileBins] bin.
class CameraColorFit {
  const CameraColorFit({
    required this.hueShift,
    required this.satMul,
    required this.lumMul,
  });

  final List<double> hueShift;
  final List<double> satMul;
  final List<double> lumMul;

  Map<String, dynamic> toJson() => {
    'hue': hueShift,
    'sat': satMul,
    'lum': lumMul,
  };

  static CameraColorFit? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    List<double>? list(Object? v) => v is List && v.length == colorProfileBins
        ? [for (final x in v) (x as num).toDouble()]
        : null;
    final hue = list(raw['hue']);
    final sat = list(raw['sat']);
    final lum = list(raw['lum']);
    if (hue == null || sat == null || lum == null) {
      return null;
    }
    return CameraColorFit(hueShift: hue, satMul: sat, lumMul: lum);
  }
}

/// Block means of [rgb] in linear light on a [cols] by [rows] grid, three
/// doubles per block. Both frames are laid out on the same grid, so block
/// `(c, r)` of each is the same patch of the scene — the alignment the
/// per-pixel comparison this file avoids would need, coarse enough not to
/// mind a crop of a percent or two.
Float64List _blockMeansLinear(
  Uint8List rgb,
  int width,
  int height,
  int cols,
  int rows,
) {
  final out = Float64List(cols * rows * 3);
  final counts = Int32List(cols * rows);
  final pixels = width * height;
  final stride = pixels <= 600000 ? 1 : (pixels / 600000).ceil();
  for (var px = 0; px < pixels; px += stride) {
    final x = px % width;
    final y = px ~/ width;
    final c = (x * cols ~/ width).clamp(0, cols - 1);
    final r = (y * rows ~/ height).clamp(0, rows - 1);
    final block = r * cols + c;
    final i = px * 3;
    out[block * 3] += srgbToLinear(rgb[i] / 255.0);
    out[block * 3 + 1] += srgbToLinear(rgb[i + 1] / 255.0);
    out[block * 3 + 2] += srgbToLinear(rgb[i + 2] / 255.0);
    counts[block]++;
  }
  for (var b = 0; b < cols * rows; b++) {
    final n = counts[b];
    if (n > 0) {
      out[b * 3] /= n;
      out[b * 3 + 1] /= n;
      out[b * 3 + 2] /= n;
    }
  }
  return out;
}

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

double _lerpTone(List<double> table, double x) {
  final n = table.length;
  final f = x.clamp(0.0, 1.0) * (n - 1);
  final i0 = f.floor().clamp(0, n - 1);
  final i1 = (i0 + 1).clamp(0, n - 1);
  return table[i0] + (table[i1] - table[i0]) * (f - i0);
}

/// Fits the camera's per-hue colour rendering: how much more (or less)
/// saturated, brighter and rotated each hue is in the camera's JPEG than
/// in the decode after [tone] — the tone curve fitted alongside — has
/// matched its brightness. Null when the two frames do not line up
/// (block brightness correlation under [calCameraColorMinCorrelation]) or
/// carry no colour to compare.
///
/// Measured the way `applyColorProfile` spends it: in linear light, hue
/// bins of the decode's own hue, the near-grey blocks weighted down by
/// the same chroma mask, so a fitted multiplier lands on the same pixels
/// it was measured on. Bins with too little colour borrow from their
/// neighbours; the table is smoothed and clamped (see the `calCamera*`
/// bounds) so a bin seen on a handful of blocks stays mild.
CameraColorFit? cameraColorFit(
  Uint8List rgbBytes,
  int width,
  int height,
  Uint8List cameraRgb,
  int cameraWidth,
  int cameraHeight, {
  List<double>? tone,
  int cols = 48,
  int rows = 32,
  double minCorrelation = calCameraColorMinCorrelation,
}) {
  if (width <= 0 || height <= 0 || cameraWidth <= 0 || cameraHeight <= 0) {
    return null;
  }
  final ours = _blockMeansLinear(rgbBytes, width, height, cols, rows);
  final camera = _blockMeansLinear(
    cameraRgb,
    cameraWidth,
    cameraHeight,
    cols,
    rows,
  );
  final blocks = cols * rows;

  // Are these the same picture? Block brightness, perceptually encoded,
  // should track between the two.
  final ourL = Float64List(blocks);
  final camL = Float64List(blocks);
  var meanA = 0.0, meanB = 0.0;
  for (var b = 0; b < blocks; b++) {
    ourL[b] = perceptualEncode(
      0.2126 * ours[b * 3] +
          0.7152 * ours[b * 3 + 1] +
          0.0722 * ours[b * 3 + 2],
    );
    camL[b] = perceptualEncode(
      0.2126 * camera[b * 3] +
          0.7152 * camera[b * 3 + 1] +
          0.0722 * camera[b * 3 + 2],
    );
    meanA += ourL[b];
    meanB += camL[b];
  }
  meanA /= blocks;
  meanB /= blocks;
  var cov = 0.0, varA = 0.0, varB = 0.0;
  for (var b = 0; b < blocks; b++) {
    final da = ourL[b] - meanA;
    final db = camL[b] - meanB;
    cov += da * db;
    varA += da * da;
    varB += db * db;
  }
  if (varA <= 1e-9 || varB <= 1e-9) {
    return null;
  }
  final correlation = cov / math.sqrt(varA * varB);
  if (correlation < minCorrelation) {
    return null;
  }

  final weight = Float64List(colorProfileBins);
  final satOurs = Float64List(colorProfileBins);
  final satCam = Float64List(colorProfileBins);
  final lumOurs = Float64List(colorProfileBins);
  final lumCam = Float64List(colorProfileBins);
  final hueSin = Float64List(colorProfileBins);
  final hueCos = Float64List(colorProfileBins);
  const binWidth = 360.0 / colorProfileBins;
  for (var b = 0; b < blocks; b++) {
    var r = ours[b * 3], g = ours[b * 3 + 1], bl = ours[b * 3 + 2];
    final linLuma = math.max(0.2126 * r + 0.7152 * g + 0.0722 * bl, 1e-6);
    if (tone != null) {
      final pIn = perceptualEncode(linLuma);
      final scale =
          perceptualDecode(_lerpTone(tone, pIn).clamp(0.0, 2.0)) / linLuma;
      r *= scale;
      g *= scale;
      bl *= scale;
    }
    final (hue, sat, val) = rgbToHsv(r, g, bl);
    if (val < 0.02 || val > 0.98) {
      continue;
    }
    final mask = _smoothstep(0.04, 0.18, sat);
    if (mask < 0.05) {
      continue;
    }
    final cr = camera[b * 3], cg = camera[b * 3 + 1], cb = camera[b * 3 + 2];
    final (camHue, camSat, camVal) = rgbToHsv(cr, cg, cb);
    if (camVal < 0.02 || camVal > 0.98) {
      continue;
    }
    final bin = ((hue / binWidth).floor()) % colorProfileBins;
    final ourLuma = 0.2126 * r + 0.7152 * g + 0.0722 * bl;
    final camLuma = 0.2126 * cr + 0.7152 * cg + 0.0722 * cb;
    var dh = camHue - hue;
    if (dh > 180) dh -= 360;
    if (dh < -180) dh += 360;
    weight[bin] += mask;
    satOurs[bin] += mask * sat;
    satCam[bin] += mask * camSat;
    lumOurs[bin] += mask * ourLuma;
    lumCam[bin] += mask * camLuma;
    hueSin[bin] += mask * math.sin(dh * math.pi / 180);
    hueCos[bin] += mask * math.cos(dh * math.pi / 180);
  }
  var total = 0.0;
  for (final w in weight) {
    total += w;
  }
  if (total < 8) {
    return null;
  }
  final satMul = List<double>.filled(colorProfileBins, double.nan);
  final lumMul = List<double>.filled(colorProfileBins, double.nan);
  final hueShift = List<double>.filled(colorProfileBins, double.nan);
  for (var i = 0; i < colorProfileBins; i++) {
    if (weight[i] < math.max(2.0, total * 0.01) ||
        satOurs[i] <= 0 ||
        lumOurs[i] <= 0) {
      continue;
    }
    satMul[i] = satCam[i] / satOurs[i];
    lumMul[i] = lumCam[i] / lumOurs[i];
    hueShift[i] = math.atan2(hueSin[i], hueCos[i]) * 180 / math.pi;
  }
  _fillGaps(satMul, 1.0);
  _fillGaps(lumMul, 1.0);
  _fillGaps(hueShift, 0.0);
  return CameraColorFit(
    hueShift: [
      for (final v in _smoothCircular(hueShift))
        v.clamp(-calCameraHueShiftLimitDeg, calCameraHueShiftLimitDeg),
    ],
    satMul: [
      for (final v in _smoothCircular(satMul))
        v.clamp(calCameraSatMulMin, calCameraSatMulMax),
    ],
    lumMul: [
      for (final v in _smoothCircular(lumMul))
        v.clamp(calCameraLumMulMin, calCameraLumMulMax),
    ],
  );
}

/// A bin with no measurement takes the average of its nearest measured
/// neighbours on either side, or [identity] when nothing was measured.
void _fillGaps(List<double> table, double identity) {
  final n = table.length;
  final measured = [
    for (var i = 0; i < n; i++)
      if (!table[i].isNaN) i,
  ];
  if (measured.isEmpty) {
    for (var i = 0; i < n; i++) {
      table[i] = identity;
    }
    return;
  }
  for (var i = 0; i < n; i++) {
    if (!table[i].isNaN) {
      continue;
    }
    var left = i, right = i;
    var dl = 0, dr = 0;
    while (table[left].isNaN) {
      left = (left - 1 + n) % n;
      dl++;
    }
    while (table[right].isNaN) {
      right = (right + 1) % n;
      dr++;
    }
    table[i] = (table[left] * dr + table[right] * dl) / (dl + dr);
  }
}

/// A three-tap [0.25, 0.5, 0.25] smoothing around the hue circle.
List<double> _smoothCircular(List<double> table) {
  final n = table.length;
  return [
    for (var i = 0; i < n; i++)
      0.25 * table[(i - 1 + n) % n] +
          0.5 * table[i] +
          0.25 * table[(i + 1) % n],
  ];
}

/// The largest brightening, in stops, that [rgbBytes] can take before it
/// clips more of the frame than [preview] does (plus [marginFraction]).
///
/// Used by libraw.dart to cap the decode-time gain: matching the camera's
/// *mean* with a pure linear gain over-brightens the highlights wherever
/// the camera's own curve has a shoulder — measured 5.6% of a frame
/// clipped against the camera's 0.6%. The gain stops where the clipping
/// would pass the camera's, and the camera tone curve, which has that
/// shoulder, carries the rest of the brightness.
///
/// Per pixel the channel that clips first is the brightest one, so the
/// cap is the gain that puts the (1 - fraction) quantile of the brightest
/// linear channel at white.
double decodeGainCapStops(
  Uint8List rgbBytes,
  EmbeddedPreview preview, {
  double marginFraction = 0.002,
}) {
  final cameraRgb = preview.image.getBytes(order: img.ChannelOrder.rgb);
  final allowed = (_clippedFraction(cameraRgb) + marginFraction).clamp(
    marginFraction,
    0.5,
  );
  final pixels = rgbBytes.length ~/ 3;
  if (pixels == 0) {
    return 0;
  }
  final stride = pixels <= _statsSampleTarget
      ? 1
      : (pixels / _statsSampleTarget).ceil();
  final peaks = <double>[];
  for (var px = 0; px < pixels; px += stride) {
    final i = px * 3;
    final m = math.max(rgbBytes[i], math.max(rgbBytes[i + 1], rgbBytes[i + 2]));
    peaks.add(srgbToLinear(m / 255.0));
  }
  peaks.sort();
  final index = ((1.0 - allowed) * (peaks.length - 1)).floor().clamp(
    0,
    peaks.length - 1,
  );
  final q = peaks[index];
  if (q <= 0) {
    return double.infinity;
  }
  return math.log(1.0 / q) / math.ln2;
}

/// Fraction of pixels with at least one channel at (or a level under)
/// white — what "clipped" means for an 8-bit frame from either source.
double _clippedFraction(Uint8List rgb) {
  final pixels = rgb.length ~/ 3;
  if (pixels == 0) {
    return 0;
  }
  final stride = pixels <= _statsSampleTarget
      ? 1
      : (pixels / _statsSampleTarget).ceil();
  var clipped = 0;
  var counted = 0;
  for (var px = 0; px < pixels; px += stride) {
    final i = px * 3;
    if (rgb[i] >= 254 || rgb[i + 1] >= 254 || rgb[i + 2] >= 254) {
      clipped++;
    }
    counted++;
  }
  return clipped / counted;
}

/// The camera's embedded JPEG, decoded once. A 13 MP preview costs about a
/// second to decode in pure Dart, and a RAW open now reads it twice — for
/// the decode-time brightness in libraw.dart and for the camera match on
/// the finished decode — so both take this instead of the bytes.
class EmbeddedPreview {
  const EmbeddedPreview._(this.bytes, this.image);

  final Uint8List bytes;
  final img.Image image;

  /// `null` for no bytes, bytes that are not a JPEG, or an empty image.
  static EmbeddedPreview? decode(Uint8List? bytes) {
    if (bytes == null) {
      return null;
    }
    img.Image? jpeg;
    try {
      jpeg = img.decodeJpg(bytes);
    } on Exception {
      jpeg = null;
    }
    if (jpeg == null || jpeg.width == 0 || jpeg.height == 0) {
      return null;
    }
    return EmbeddedPreview._(bytes, jpeg);
  }
}

/// What a decode learns by comparing itself against the camera's own
/// embedded rendering of the same shot: how far off it is overall, and how
/// its tonality is distributed.
///
/// The two are measured from the same pair and are always present or
/// absent together. They are alternatives, not layers — see
/// [cameraToneCurve].
class CameraMatch {
  const CameraMatch({this.stops, this.tone, this.color});

  static const none = CameraMatch();

  final double? stops;
  final List<double>? tone;

  /// The camera's per-hue colour rendering — see [cameraColorFit].
  final CameraColorFit? color;

  bool get isEmpty => stops == null && tone == null && color == null;

  Map<String, dynamic> toJson() => {
    'stops': stops,
    'tone': tone,
    'color': color?.toJson(),
  };

  /// Null for anything that is not a match this app wrote — a corrupt or
  /// truncated cache entry reads as "not measured yet" rather than as a
  /// curve of the wrong length, which would be applied without complaint.
  static CameraMatch? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final tone = raw['tone'];
    final stops = raw['stops'];
    if (tone is! List || tone.length != colorProfileTonePoints) {
      return null;
    }
    // An entry from before the colour fit existed (2026-09-12) reads as
    // not measured, so the photo is measured again once and the fit
    // stored with it.
    if (!raw.containsKey('color')) {
      return null;
    }
    final colorRaw = raw['color'];
    return CameraMatch(
      stops: stops is num ? stops.toDouble() : null,
      tone: [for (final v in tone) (v as num).toDouble()],
      color: colorRaw == null ? null : CameraColorFit.fromJson(colorRaw),
    );
  }
}
