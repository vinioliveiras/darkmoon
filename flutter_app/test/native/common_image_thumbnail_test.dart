import 'dart:typed_data';

import 'package:darkmoon/native/common_image_thumbnail.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Builds a flat-color JPEG, optionally tagging it with an EXIF
/// orientation, for exercising the hand-rolled EXIF reader and the
/// dart:ui-based scaled decode without needing a real camera file on disk.
Uint8List _makeJpeg({
  required int width,
  required int height,
  int? orientation,
  int r = 200,
  int g = 40,
  int b = 40,
}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  if (orientation != null) {
    image.exif.imageIfd.orientation = orientation;
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  group('readJpegExifOrientation', () {
    test('no EXIF data returns 1 (normal)', () {
      final bytes = _makeJpeg(width: 40, height: 20);
      expect(readJpegExifOrientation(bytes), 1);
    });

    test('reads a tagged orientation back correctly', () {
      for (final orientation in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final bytes = _makeJpeg(
          width: 40,
          height: 20,
          orientation: orientation,
        );
        expect(
          readJpegExifOrientation(bytes),
          orientation,
          reason: 'orientation $orientation',
        );
      }
    });

    test('non-JPEG bytes return 1 rather than throwing', () {
      expect(readJpegExifOrientation(Uint8List.fromList([0, 1, 2, 3])), 1);
      expect(readJpegExifOrientation(Uint8List(0)), 1);
    });
  });

  group('decodeJpegThumbnailFast', () {
    test('downscales a large JPEG to the thumbnail cap', () async {
      final bytes = _makeJpeg(width: 2000, height: 1000);
      final result = await decodeJpegThumbnailFast(bytes);
      expect(result, isNotNull);
      final decoded = img.decodeJpg(result!);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(200));
      expect(decoded.height, lessThanOrEqualTo(200));
      // 2000x1000 at cap 200 -> 200x100.
      expect(decoded.width, 200);
      expect(decoded.height, 100);
    });

    test('leaves an already-small JPEG at its native size', () async {
      final bytes = _makeJpeg(width: 80, height: 40);
      final result = await decodeJpegThumbnailFast(bytes);
      final decoded = img.decodeJpg(result!);
      expect(decoded!.width, 80);
      expect(decoded.height, 40);
    });

    test('bakes a 90-degree EXIF rotation into the output pixels', () async {
      // Orientation 6 = rotate 90 CW to display correctly, so a landscape
      // source should come out portrait.
      final bytes = _makeJpeg(width: 2000, height: 1000, orientation: 6);
      final result = await decodeJpegThumbnailFast(bytes);
      final decoded = img.decodeJpg(result!);
      expect(decoded!.width, 100);
      expect(decoded.height, 200);
    });

    test(
      'preserves color through the downscale/re-encode round trip',
      () async {
        final bytes = _makeJpeg(width: 800, height: 400, r: 10, g: 200, b: 10);
        final result = await decodeJpegThumbnailFast(bytes);
        final decoded = img.decodeJpg(result!);
        final pixel = decoded!.getPixel(
          decoded.width ~/ 2,
          decoded.height ~/ 2,
        );
        // JPEG quantization + chroma subsampling introduces some drift on a
        // flat color, so this checks "still green", not exact equality.
        expect(pixel.g, greaterThan(pixel.r));
        expect(pixel.g, greaterThan(pixel.b));
      },
    );
  });
}
