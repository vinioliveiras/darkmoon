import 'package:image/image.dart' as img;

/// Downscales [image] so its longest side is at most [maxDimension],
/// preserving aspect ratio. Returns [image] unchanged if it's already
/// small enough (never upscales).
img.Image fitToMaxDimension(img.Image image, int maxDimension) {
  final longestSide = image.width > image.height ? image.width : image.height;
  if (longestSide <= maxDimension) {
    return image;
  }
  return image.width >= image.height
      ? img.copyResize(image, width: maxDimension)
      : img.copyResize(image, height: maxDimension);
}
