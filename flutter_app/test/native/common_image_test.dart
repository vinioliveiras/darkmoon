import 'dart:io';

import 'package:darkmoon/native/common_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Writes [bytes] to a fresh temp file and returns its path — [decodeCommonImage]
/// reads from disk, not from a byte buffer, so every case needs a real file.
String _writeTempFile(String name, List<int> bytes) {
  final dir = Directory.systemTemp.createTempSync('common_image_test');
  final file = File('${dir.path}/$name');
  file.writeAsBytesSync(bytes);
  return file.path;
}

void main() {
  group('decodeCommonImage', () {
    test('a plain 8-bit RGB PNG decodes to the exact color', () {
      final image = img.Image(width: 4, height: 3);
      img.fill(image, color: img.ColorRgb8(200, 40, 120));
      final path = _writeTempFile('flat.png', img.encodePng(image));

      final result = decodeCommonImage(path);

      expect(result, isNotNull);
      expect(result!.width, 4);
      expect(result.height, 3);
      expect(result.rgbBytes.length, 4 * 3 * 3);
      expect(result.rgbBytes.sublist(0, 3), [200, 40, 120]);
    });

    // Real bug (2026-09-01): a 16-bit-per-channel TIFF (a real Fujifilm
    // camera TIFF export) rendered as pure RGB noise. `getBytes` only
    // reorders channels — for a non-uint8 source it hands back the image's
    // native buffer untouched (2 bytes/channel here), which every caller of
    // `RawImage.rgbBytes` assumes is already packed 8-bit RGB (3 bytes/
    // pixel). Every downstream pixel index landed on the wrong byte,
    // producing static. `decodeCommonImage` must normalize bit depth (and
    // channel count) before extracting bytes.
    test('a 16-bit-per-channel TIFF decodes to the correctly-scaled color, '
        'not raw noise', () {
      final image = img.Image(
        width: 5,
        height: 4,
        format: img.Format.uint16,
        numChannels: 3,
      );
      // 40000/65535 and 4000/65535 scale to roughly 155 and 16 in 8-bit —
      // picked to be far from both 0 and 255 so a byte-alignment bug (which
      // would scatter high/low bytes essentially at random) is very unlikely
      // to coincidentally land back in-range.
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          image.setPixelRgb(x, y, 40000, 4000, 60000);
        }
      }
      final path = _writeTempFile(
        'sixteen_bit.tif',
        img.TiffEncoder().encode(image),
      );

      final result = decodeCommonImage(path);

      expect(result, isNotNull);
      expect(result!.width, 5);
      expect(result.height, 4);
      // Packed 8-bit RGB — exactly 3 bytes/pixel, not 6.
      expect(result.rgbBytes.length, 5 * 4 * 3);
      final r = result.rgbBytes[0];
      final g = result.rgbBytes[1];
      final b = result.rgbBytes[2];
      expect(r, closeTo(40000 / 65535 * 255, 2));
      expect(g, closeTo(4000 / 65535 * 255, 2));
      expect(b, closeTo(60000 / 65535 * 255, 2));
      // Every pixel should be identical (flat-filled source) — a stride/
      // byte-alignment bug would make neighbouring pixels disagree.
      for (var i = 3; i < result.rgbBytes.length; i += 3) {
        expect(result.rgbBytes[i], r);
        expect(result.rgbBytes[i + 1], g);
        expect(result.rgbBytes[i + 2], b);
      }
    });

    test('an RGBA PNG (alpha channel) drops alpha and stays 3 bytes/pixel', () {
      final image = img.Image(width: 3, height: 2, numChannels: 4);
      img.fill(image, color: img.ColorRgba8(10, 20, 30, 128));
      final path = _writeTempFile('alpha.png', img.encodePng(image));

      final result = decodeCommonImage(path);

      expect(result, isNotNull);
      expect(result!.rgbBytes.length, 3 * 2 * 3);
      expect(result.rgbBytes.sublist(0, 3), [10, 20, 30]);
    });

    test('a missing file returns null', () {
      expect(
        () => decodeCommonImage(
          '${Directory.systemTemp.path}/does_not_exist.png',
        ),
        throwsA(isA<PathNotFoundException>()),
      );
    });
  });
}
