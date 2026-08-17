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
