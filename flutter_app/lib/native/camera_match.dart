import 'dart:math' as math;
import 'dart:typed_data';

import '../render/calibration.dart';

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
