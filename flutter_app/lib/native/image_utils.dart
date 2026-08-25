import 'package:image/image.dart' as img;

/// Downscales [image] so its longest side is at most [maxDimension],
/// preserving aspect ratio. Returns [image] unchanged if it's already
/// small enough (never upscales).
///
/// Uses area-averaging (box filter) instead of nearest-neighbor so the
/// preview downscale reduces sensor noise like Lightroom does, instead of
/// preserving full-amplitude noise by subsampling one pixel per block.
img.Image fitToMaxDimension(img.Image image, int maxDimension) {
  final longestSide = image.width > image.height ? image.width : image.height;
  if (longestSide <= maxDimension) {
    return image;
  }
  final double scale = maxDimension / longestSide;
  final int targetWidth = (image.width * scale).round();
  final int targetHeight = (image.height * scale).round();
  return img.copyResize(
    image,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.average,
  );
}

/// Scales [image] to [percent] of its own native size (1-100), preserving
/// aspect ratio. Returns [image] unchanged at 100 (or above — never
/// upscales). Backs the export dialog's "Rapid export" resolution slider,
/// which works in percent-of-original rather than [fitToMaxDimension]'s
/// absolute pixel cap since there's no single target size that makes sense
/// across every camera's sensor resolution.
///
/// Uses the same area-averaging (box filter) as [fitToMaxDimension], for
/// the same reason: it reduces sensor noise the way Lightroom's own
/// downscale does, instead of preserving full-amplitude noise the way
/// nearest-neighbor subsampling would.
img.Image scaleByPercent(img.Image image, int percent) {
  if (percent >= 100) {
    return image;
  }
  final targetWidth = (image.width * percent / 100).round();
  final targetHeight = (image.height * percent / 100).round();
  return img.copyResize(
    image,
    width: targetWidth,
    height: targetHeight,
    interpolation: img.Interpolation.average,
  );
}
