import 'dart:typed_data';

import 'package:darkmoon/catalog/jpeg_size.dart';
import 'package:flutter_test/flutter_test.dart';

/// A JPEG's size comes from its frame header, past whatever application
/// segments precede it; anything else reads as unknown.
void main() {
  Uint8List jpeg({required int width, required int height}) =>
      Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x10, // APP0, 16 bytes long
        0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01,
        0x00, 0x00,
        0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, 17 bytes, 8-bit
        height >> 8, height & 0xFF, width >> 8, width & 0xFF,
        0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
        0xFF, 0xD9, // EOI
      ]);

  test('reads the frame header past the application segment', () {
    expect(jpegSizeOf(jpeg(width: 320, height: 213)), (
      width: 320,
      height: 213,
    ));
    expect(jpegSizeOf(jpeg(width: 213, height: 320)), (
      width: 213,
      height: 320,
    ));
  });

  test('is null for anything that is not a JPEG', () {
    expect(jpegSizeOf(Uint8List.fromList([0])), isNull);
    expect(jpegSizeOf(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), isNull);
    expect(jpegSizeOf(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9])), isNull);
  });
}
