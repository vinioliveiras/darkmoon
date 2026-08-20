import 'dart:typed_data';

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
