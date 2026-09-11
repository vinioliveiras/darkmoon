import 'dart:typed_data';

/// The pixel size a JPEG declares in its frame header, read from the
/// first few segments without decoding anything; null for anything that
/// is not a JPEG or is cut off before the frame header.
///
/// The album covers use it to tell a portrait thumbnail from a landscape
/// one and lay the mosaic out to fit.
({int width, int height})? jpegSizeOf(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  var i = 2;
  while (i + 3 < bytes.length) {
    if (bytes[i] != 0xFF) {
      return null;
    }
    final marker = bytes[i + 1];
    if (marker == 0xFF) {
      // Fill byte before a marker.
      i++;
      continue;
    }
    if (marker == 0xD8 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0x01) {
      // Standalone markers carry no length.
      i += 2;
      continue;
    }
    final length = (bytes[i + 2] << 8) | bytes[i + 3];
    final isFrameHeader =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrameHeader) {
      if (i + 8 >= bytes.length) {
        return null;
      }
      final height = (bytes[i + 5] << 8) | bytes[i + 6];
      final width = (bytes[i + 7] << 8) | bytes[i + 8];
      return (width: width, height: height);
    }
    if (marker == 0xDA || marker == 0xD9) {
      // Scan data or end of image: no frame header came first.
      return null;
    }
    i += 2 + length;
  }
  return null;
}
