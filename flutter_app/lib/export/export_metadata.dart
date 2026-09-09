import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../native/libraw.dart' show RawMetadata;

/// The capture facts an exported file should carry about the photo it
/// came from — camera, lens and exposure. Built on the main isolate from
/// the [RawMetadata] the editor already holds for each photo, and handed
/// to the export isolate inside the request.
///
/// Until 2026-09-09 an export wrote no metadata at all: a RAW edited here
/// left as a JPEG with no camera, no lens, no ISO, no shutter, no
/// aperture — the same file exported from Meridian keeps all of them, and
/// every photo site, catalog and "info" panel reads them.
class ExportCaptureInfo {
  const ExportCaptureInfo({
    this.make = '',
    this.model = '',
    this.lens = '',
    this.iso = 0,
    this.shutterSeconds = 0,
    this.fNumber = 0,
    this.focalLengthMm = 0,
  });

  factory ExportCaptureInfo.fromRawMetadata(RawMetadata metadata) =>
      ExportCaptureInfo(
        make: metadata.cameraMake,
        model: metadata.cameraModel,
        lens: metadata.lensModel,
        iso: metadata.isoSpeed,
        shutterSeconds: metadata.shutterSeconds,
        fNumber: metadata.apertureFNumber,
        focalLengthMm: metadata.focalLengthMm,
      );

  final String make;
  final String model;
  final String lens;

  /// 0 when unknown, like every numeric field here.
  final double iso;
  final double shutterSeconds;
  final double fNumber;
  final double focalLengthMm;

  bool get isEmpty =>
      make.isEmpty &&
      model.isEmpty &&
      lens.isEmpty &&
      iso <= 0 &&
      shutterSeconds <= 0 &&
      fNumber <= 0 &&
      focalLengthMm <= 0;
}

/// The source file's own EXIF block, for a JPEG source; `null` for
/// anything else, for a JPEG without one, and for a file that cannot be
/// read. Parses the headers only — the pixels are never decoded.
img.ExifData? readSourceExif(String path) {
  final ext = p.extension(path).toLowerCase();
  if (ext != '.jpg' && ext != '.jpeg') {
    return null;
  }
  try {
    return _exifFromJpegHeaders(File(path).readAsBytesSync());
  } catch (_) {
    return null;
  }
}

/// Walks the JPEG marker segments up to the first scan and parses the
/// `Exif\0\0` APP1 segment if there is one. `package:image` 4.8 only
/// surfaces EXIF after a full pixel decode, which a 20 MP source does not
/// deserve for a few hundred bytes of headers.
img.ExifData? _exifFromJpegHeaders(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    return null;
  }
  var pos = 2;
  while (pos + 4 <= bytes.length) {
    if (bytes[pos] != 0xff) {
      return null;
    }
    final marker = bytes[pos + 1];
    if (marker == 0xff) {
      pos++;
      continue;
    }
    // Standalone markers carry no length.
    if (marker == 0xd8 ||
        marker == 0x01 ||
        (marker >= 0xd0 && marker <= 0xd7)) {
      pos += 2;
      continue;
    }
    if (marker == 0xda || marker == 0xd9) {
      return null; // start of scan / end of image: no APP1 before it
    }
    final length = (bytes[pos + 2] << 8) | bytes[pos + 3];
    final segmentEnd = pos + 2 + length;
    if (length < 2 || segmentEnd > bytes.length) {
      return null;
    }
    if (marker == 0xe1 && length >= 8) {
      const signature = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // Exif\0\0
      var matches = true;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[pos + 4 + i] != signature[i]) {
          matches = false;
          break;
        }
      }
      if (matches) {
        final payload = Uint8List.sublistView(
          bytes,
          pos + 4 + signature.length,
          segmentEnd,
        );
        final exif = img.ExifData.fromInputBuffer(img.InputBuffer(payload));
        return exif.isEmpty ? null : exif;
      }
    }
    pos = segmentEnd;
  }
  return null;
}

/// The EXIF block an export of [width]x[height] pixels is written with.
///
/// Starts from [sourceExif] when there is one (a JPEG source keeps
/// everything its camera wrote — dates, GPS, maker notes), then fixes the
/// tags that describe the *pixels*, which the export changed: orientation
/// is 1 because the pixels are written upright, the two size pairs are
/// the export's own, the embedded thumbnail (IFD1) is dropped because it
/// would show the unedited frame, and Software names this app.
/// [capture] then fills in any camera/exposure tag still missing — for a
/// RAW source that is all of them.
img.ExifData buildExportExif({
  required int width,
  required int height,
  img.ExifData? sourceExif,
  ExportCaptureInfo? capture,
}) {
  final exif = sourceExif?.clone() ?? img.ExifData();
  final image = exif.imageIfd;
  final sub = exif.exifIfd;

  // Explicit IfdValue objects throughout: assigning a plain int/String/List
  // by tag name relies on the package's tag-type table, which in 4.8.0 has
  // no entry for FNumber, FocalLength or the Exif-IFD size pair — those
  // assignments were dropped without a word.
  exif.directories.remove('ifd1');
  image['Orientation'] = img.IfdValueShort(1);
  image['ImageWidth'] = img.IfdValueLong(width);
  image['ImageLength'] = img.IfdValueLong(height);
  sub['ExifImageWidth'] = img.IfdValueLong(width);
  sub['ExifImageLength'] = img.IfdValueLong(height);
  image['Software'] = img.IfdValueAscii('darkmoon');

  if (capture != null && !capture.isEmpty) {
    void fill(img.IfdDirectory dir, String tag, img.IfdValue? value) {
      if (value != null && dir[tag] == null) {
        dir[tag] = value;
      }
    }

    fill(image, 'Make', _ascii(capture.make));
    fill(image, 'Model', _ascii(capture.model));
    fill(sub, 'LensModel', _ascii(capture.lens));
    fill(
      sub,
      'ISOSpeed',
      capture.iso > 0 ? img.IfdValueShort(capture.iso.round()) : null,
    );
    fill(sub, 'ExposureTime', _exposureTimeRational(capture.shutterSeconds));
    fill(sub, 'FNumber', _tenthsRational(capture.fNumber));
    fill(sub, 'FocalLength', _tenthsRational(capture.focalLengthMm));
  }
  return exif;
}

img.IfdValueAscii? _ascii(String value) =>
    value.isEmpty ? null : img.IfdValueAscii(value);

/// `1/250` stays `1/250`; a second or longer becomes `n/1000`. Null for a
/// missing value.
img.IfdValueRational? _exposureTimeRational(double seconds) {
  if (seconds <= 0) {
    return null;
  }
  if (seconds >= 1) {
    return img.IfdValueRational((seconds * 1000).round(), 1000);
  }
  return img.IfdValueRational(1, (1 / seconds).round());
}

img.IfdValueRational? _tenthsRational(double value) =>
    value <= 0 ? null : img.IfdValueRational((value * 10).round(), 10);
