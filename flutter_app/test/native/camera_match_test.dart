import 'dart:typed_data';

import 'package:darkmoon/native/camera_match.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Uint8List _flatJpeg(int width, int height, int r, int g, int b) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image, quality: 95));
}

Uint8List _flatRgb(int width, int height, int r, int g, int b) {
  final bytes = Uint8List(width * height * 3);
  for (var i = 0; i < bytes.length; i += 3) {
    bytes[i] = r;
    bytes[i + 1] = g;
    bytes[i + 2] = b;
  }
  return bytes;
}

void main() {
  group('applyCameraMatch', () {
    test('null embedded JPEG leaves the buffer unchanged', () {
      final rgb = _flatRgb(4, 4, 100, 120, 140);
      final result = applyCameraMatch(rgb, 4, 4, null);
      expect(result, same(rgb));
      expect(result, everyElement(anyOf(100, 120, 140)));
    });

    test('unparseable embedded JPEG bytes leave the buffer unchanged', () {
      final rgb = _flatRgb(4, 4, 100, 120, 140);
      final result = applyCameraMatch(
        rgb,
        4,
        4,
        Uint8List.fromList([1, 2, 3, 4]),
      );
      expect(result[0], 100);
      expect(result[1], 120);
      expect(result[2], 140);
    });

    test('nudges a flat color toward the embedded JPEG, within the gain '
        'clamp', () {
      // Demosaic came out a bit dark/flat; the camera's own JPEG rendered
      // the same (aspect-matched) scene brighter — expect the raw buffer
      // to move toward, but not necessarily all the way to, the JPEG's
      // color, and never past it (gain is a multiplicative nudge, so an
      // already-zero channel can't be lifted).
      final rgb = _flatRgb(100, 100, 100, 100, 100);
      final jpeg = _flatJpeg(100, 100, 150, 110, 90);
      final result = applyCameraMatch(rgb, 100, 100, jpeg);
      expect(result[0], greaterThan(100));
      expect(result[0], lessThanOrEqualTo(120)); // gain clamped to 1.2x
      expect(result[1], closeTo(110, 5));
      expect(result[2], lessThanOrEqualTo(100));
    });

    test('mismatched aspect ratio (rotated crop) is left unchanged', () {
      final rgb = _flatRgb(200, 100, 100, 100, 100);
      // Same scene, but the "embedded thumbnail" is portrait-oriented —
      // its mean color isn't a trustworthy comparison for a landscape
      // decode, so the aspect-ratio guard should skip the match entirely.
      final jpeg = _flatJpeg(100, 200, 200, 200, 200);
      final result = applyCameraMatch(rgb, 200, 100, jpeg);
      expect(result[0], 100);
      expect(result[1], 100);
      expect(result[2], 100);
    });
  });
}
