import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Same cap as [thumbnailMaxDimension] in thumbnail_loader.dart — kept as
/// its own constant so this file doesn't need to import that one just for
/// a number (avoids pulling in its `dart:io` dependency on a code path
/// that's meant to run on the main isolate).
const _fastThumbnailMaxDimension = 200;

/// Fast-path thumbnail decode for JPEG common images, using the platform's
/// native (Skia, via `dart:ui`) decoder to downscale *while* decoding
/// instead of decoding at full resolution first the way
/// `decodeCommonImage`/[decodeRawThumbnail] do via `package:image` — for a
/// 24-60MP camera JPEG, decoding every pixel just to immediately throw
/// most of them away in a resize is the dominant cost (`package:image` has
/// no scaled-decode option; Skia's libjpeg-backed decoder does, via DCT
/// scaling, and is dramatically cheaper for large source images).
///
/// Must run on the isolate that owns the Flutter engine — `dart:ui` isn't
/// available on a background `compute()`/`Isolate.spawn` isolate — so
/// unlike every other thumbnail decode path in this app, callers await
/// this directly on the main isolate rather than routing it through
/// `compute()`. The actual pixel decode still happens off the Dart UI
/// thread (in the engine's own decode worker), so this doesn't block the
/// event loop the way a synchronous `package:image` decode would.
///
/// Only handles JPEG — PNG/WebP/BMP/TIFF common images still go through
/// the full-decode path (rarely huge camera output, so there's no
/// scaled-decode win worth the extra code path here).
Future<Uint8List?> decodeJpegThumbnailFast(Uint8List bytes) async {
  final info = img.JpegDecoder().startDecode(bytes);
  if (info == null || info.width <= 0 || info.height <= 0) {
    return null;
  }
  final target = _scaleToFit(
    info.width,
    info.height,
    _fastThumbnailMaxDimension,
  );
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: target.width,
    targetHeight: target.height,
  );
  final frame = await codec.getNextFrame();
  final uiImage = frame.image;
  final width = uiImage.width;
  final height = uiImage.height;
  final rawRgba = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  uiImage.dispose();
  if (rawRgba == null) {
    return null;
  }
  final decoded = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rawRgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  // Baking orientation on the already-downscaled image, not the source
  // bytes — same reasoning as decodeRawThumbnail's embedded-preview path:
  // a 90/180/270 rotation costs the same relative to whatever resolution
  // it runs at, so doing it after the resize is the same visual result
  // for a fraction of the pixels touched.
  decoded.exif.imageIfd.orientation = readJpegExifOrientation(bytes);
  final oriented = img.bakeOrientation(decoded);
  return Uint8List.fromList(img.encodeJpg(oriented, quality: 85));
}

({int width, int height}) _scaleToFit(int width, int height, int maxDim) {
  final longestSide = width > height ? width : height;
  if (longestSide <= maxDim) {
    return (width: width, height: height);
  }
  final scale = maxDim / longestSide;
  return (width: (width * scale).round(), height: (height * scale).round());
}

/// Reads just the EXIF orientation tag (0x0112) from a JPEG's APP1
/// segment, without decoding any pixels — cheap enough to run inline
/// before [decodeJpegThumbnailFast]'s scaled decode. `package:image`'s own
/// header-only parser ([img.JpegDecoder.startDecode]) skips APP1 entirely
/// (it only reads the SOF/SOS frame markers), so there's no existing
/// public API this could reuse. Returns 1 (no rotation) if there's no
/// EXIF/orientation data, matching the "absent = normal" convention
/// `package:image`'s own `ImageIfd.orientation` uses.
int readJpegExifOrientation(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return 1;
  }
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) {
      break;
    }
    final marker = bytes[offset + 1];
    // SOS (start of scan) means pixel data follows — every marker of
    // interest (APPn included) always comes before it.
    if (marker == 0xDA) {
      break;
    }
    if (offset + 4 > bytes.length) {
      break;
    }
    final segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (marker == 0xE1) {
      final orientation = _readExifOrientationFromApp1(
        bytes,
        offset + 4,
        segmentLength - 2,
      );
      if (orientation != null) {
        return orientation;
      }
    }
    offset += 2 + segmentLength;
  }
  return 1;
}

int? _readExifOrientationFromApp1(Uint8List bytes, int start, int length) {
  final end = start + length;
  if (end > bytes.length || start + 6 > bytes.length) {
    return null;
  }
  // "Exif\0\0" header.
  if (bytes[start] != 0x45 ||
      bytes[start + 1] != 0x78 ||
      bytes[start + 2] != 0x69 ||
      bytes[start + 3] != 0x66 ||
      bytes[start + 4] != 0x00 ||
      bytes[start + 5] != 0x00) {
    return null;
  }
  final tiffStart = start + 6;
  if (tiffStart + 8 > bytes.length) {
    return null;
  }
  final bigEndian = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
  int readU16(int o) => bigEndian
      ? (bytes[o] << 8) | bytes[o + 1]
      : (bytes[o + 1] << 8) | bytes[o];
  int readU32(int o) => bigEndian
      ? (bytes[o] << 24) |
            (bytes[o + 1] << 16) |
            (bytes[o + 2] << 8) |
            bytes[o + 3]
      : (bytes[o + 3] << 24) |
            (bytes[o + 2] << 16) |
            (bytes[o + 1] << 8) |
            bytes[o];
  final ifdOffset = readU32(tiffStart + 4);
  final ifdStart = tiffStart + ifdOffset;
  if (ifdStart + 2 > bytes.length) {
    return null;
  }
  final numEntries = readU16(ifdStart);
  for (var i = 0; i < numEntries; i++) {
    final entryStart = ifdStart + 2 + i * 12;
    if (entryStart + 12 > bytes.length) {
      break;
    }
    final tag = readU16(entryStart);
    if (tag == 0x0112) {
      return readU16(entryStart + 8);
    }
  }
  return null;
}
