import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/export/export_format.dart';
import 'package:darkmoon/export/export_job.dart';
import 'package:darkmoon/export/export_metadata.dart';
import 'package:darkmoon/export/srgb_icc.dart';
import 'package:darkmoon/native/libraw.dart' show RawMetadata;
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const _capture = ExportCaptureInfo(
  make: 'Canon',
  model: 'Canon EOS 350D',
  lens: 'EF50mm f/1.8 II',
  iso: 400,
  shutterSeconds: 1 / 250,
  fNumber: 2.8,
  focalLengthMm: 50,
);

/// Round-trips [exif] through a real JPEG encode/decode, which is what
/// every reader of an exported file sees.
img.ExifData _roundTrip(img.ExifData exif, {int width = 8, int height = 6}) {
  final image = img.Image(width: width, height: height)..exif = exif;
  final decoded = img.decodeJpg(img.encodeJpg(image));
  return decoded!.exif;
}

void main() {
  test('fromRawMetadata carries every capture field across', () {
    final metadata = RawMetadata(
      cameraMake: 'Fujifilm',
      cameraModel: 'X-T3',
      lensModel: 'XF35mmF1.4 R',
      isoSpeed: 800,
      shutterSeconds: 0.5,
      apertureFNumber: 1.4,
      focalLengthMm: 35,
      width: 6000,
      height: 4000,
      captureTime: DateTime(2026, 9, 10, 7, 5, 9),
    );
    final info = ExportCaptureInfo.fromRawMetadata(metadata);
    expect(info.captureTime, DateTime(2026, 9, 10, 7, 5, 9));
    expect(info.make, 'Fujifilm');
    expect(info.model, 'X-T3');
    expect(info.lens, 'XF35mmF1.4 R');
    expect(info.iso, 800);
    expect(info.shutterSeconds, 0.5);
    expect(info.fNumber, 1.4);
    expect(info.focalLengthMm, 35);
    expect(info.isEmpty, isFalse);
    expect(const ExportCaptureInfo().isEmpty, isTrue);
  });

  group('buildExportExif', () {
    test('from capture info alone (a RAW source) writes camera, lens and '
        'exposure tags that survive a JPEG round trip', () {
      final built = buildExportExif(width: 8, height: 6, capture: _capture);
      // package:image's decoder consumes the Orientation tag (it applies
      // it), so orientation is checked on what is written, not read back.
      expect(built.imageIfd['Orientation']!.toInt(), 1);
      final exif = _roundTrip(built);
      expect(exif.imageIfd['Make']!.toString(), 'Canon');
      expect(exif.imageIfd['Model']!.toString(), 'Canon EOS 350D');
      expect(exif.imageIfd['Software']!.toString(), 'darkmoon');
      expect(exif.exifIfd['LensModel']!.toString(), 'EF50mm f/1.8 II');
      expect(exif.exifIfd['ISOSpeed']!.toInt(), 400);
      final exposure = exif.exifIfd['ExposureTime']!.toRational();
      expect(exposure.numerator, 1);
      expect(exposure.denominator, 250);
      final fNumber = exif.exifIfd['FNumber']!.toRational();
      expect(fNumber.numerator / fNumber.denominator, closeTo(2.8, 1e-9));
      final focal = exif.exifIfd['FocalLength']!.toRational();
      expect(focal.numerator / focal.denominator, closeTo(50, 1e-9));
      expect(exif.exifIfd['ExifImageWidth']!.toInt(), 8);
      expect(exif.exifIfd['ExifImageLength']!.toInt(), 6);
    });

    test('the capture time lands in all three EXIF date tags, in EXIF\'s '
        'own layout, and survives the round trip', () {
      final exif = _roundTrip(
        buildExportExif(
          width: 4,
          height: 4,
          capture: ExportCaptureInfo(
            captureTime: DateTime(2026, 9, 10, 7, 5, 9),
          ),
        ),
      );
      expect(
        exifDateTime(DateTime(2026, 9, 10, 7, 5, 9)),
        '2026:09:10 07:05:09',
      );
      expect(
        exif.exifIfd['DateTimeOriginal']!.toString(),
        '2026:09:10 07:05:09',
      );
      expect(
        exif.exifIfd['DateTimeDigitized']!.toString(),
        '2026:09:10 07:05:09',
      );
      expect(exif.imageIfd['DateTime']!.toString(), '2026:09:10 07:05:09');
      // A source's own date is never overwritten.
      final source = img.ExifData();
      source.exifIfd['DateTimeOriginal'] = '2020:01:02 03:04:05';
      final kept = buildExportExif(
        width: 4,
        height: 4,
        sourceExif: source,
        capture: ExportCaptureInfo(captureTime: DateTime(2026, 9, 10)),
      );
      expect(
        kept.exifIfd['DateTimeOriginal']!.toString(),
        '2020:01:02 03:04:05',
      );
    });

    test('a shutter of a second or longer is written in thousandths', () {
      final exif = buildExportExif(
        width: 4,
        height: 4,
        capture: const ExportCaptureInfo(shutterSeconds: 2.5),
      );
      final exposure = exif.exifIfd['ExposureTime']!.toRational();
      expect(exposure.numerator, 2500);
      expect(exposure.denominator, 1000);
    });

    test('unknown capture values write no tag at all', () {
      final exif = buildExportExif(
        width: 4,
        height: 4,
        capture: const ExportCaptureInfo(make: 'Sony'),
      );
      expect(exif.imageIfd['Make'], isNotNull);
      expect(exif.imageIfd['Model'], isNull);
      expect(exif.exifIfd['ExposureTime'], isNull);
      expect(exif.exifIfd['FNumber'], isNull);
      expect(exif.exifIfd['ISOSpeed'], isNull);
    });

    test('a JPEG source keeps its own tags, loses its orientation, size '
        'and thumbnail, and is not overridden by capture info', () {
      final source = img.ExifData();
      source.imageIfd['Make'] = 'Nikon';
      source.imageIfd['Model'] = 'Z 6';
      source.imageIfd['Orientation'] = 6;
      source.imageIfd['ImageWidth'] = 6000;
      source.imageIfd['ImageLength'] = 4000;
      source.exifIfd['DateTimeOriginal'] = '2026:09:09 12:00:00';
      source.exifIfd['ISOSpeed'] = 100;
      source.thumbnailIfd['ImageWidth'] = 160;

      final built = buildExportExif(
        width: 3000,
        height: 2000,
        sourceExif: source,
        capture: _capture,
      );
      expect(built.imageIfd['Orientation']!.toInt(), 1);
      expect(built.directories.containsKey('ifd1'), isFalse);
      final exif = _roundTrip(built, width: 12, height: 8);
      expect(exif.imageIfd['Make']!.toString(), 'Nikon');
      expect(exif.imageIfd['Model']!.toString(), 'Z 6');
      expect(
        exif.exifIfd['DateTimeOriginal']!.toString(),
        '2026:09:09 12:00:00',
      );
      expect(exif.exifIfd['ISOSpeed']!.toInt(), 100);
      // Gaps are filled from capture info, existing tags are not touched.
      expect(exif.exifIfd['LensModel']!.toString(), 'EF50mm f/1.8 II');
      expect(exif.imageIfd['ImageWidth']!.toInt(), 3000);
      expect(exif.imageIfd['ImageLength']!.toInt(), 2000);
      expect(exif.directories.containsKey('ifd1'), isFalse);
      // The source object itself is left alone.
      expect(source.imageIfd['Orientation']!.toInt(), 6);
    });
  });

  group('readSourceExif', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('darkmoon_exif_');
    });
    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('reads a JPEG file\'s EXIF without decoding its pixels', () async {
      final exif = img.ExifData();
      exif.imageIfd['Make'] = 'Olympus';
      final image = img.Image(width: 16, height: 16)..exif = exif;
      final path = p.join(dir.path, 'shot.JPG');
      await File(path).writeAsBytes(img.encodeJpg(image));
      final read = readSourceExif(path);
      expect(read, isNotNull);
      expect(read!.imageIfd['Make']!.toString(), 'Olympus');
    });

    test('is null for a non-JPEG path, a missing file and a JPEG without '
        'EXIF', () async {
      expect(readSourceExif(p.join(dir.path, 'x.cr2')), isNull);
      expect(readSourceExif(p.join(dir.path, 'missing.jpg')), isNull);
      final bare = img.Image(width: 4, height: 4);
      final path = p.join(dir.path, 'bare.jpg');
      await File(path).writeAsBytes(img.encodeJpg(bare));
      expect(readSourceExif(path), isNull);
    });
  });

  test(
    'exportPhoto writes the capture EXIF into the JPEG it produces',
    () async {
      final dir = await Directory.systemTemp.createTemp('darkmoon_export_');
      try {
        const w = 12, h = 8;
        final rgb = Uint8List(w * h * 3);
        for (var i = 0; i < rgb.length; i++) {
          rgb[i] = (i * 7) & 0xff;
        }
        final dest = p.join(dir.path, 'out.jpg');
        final result = await exportPhoto(
          ExportRequest(
            sourcePath: p.join(dir.path, 'source.cr2'),
            destPath: dest,
            params: const RenderParams(),
            format: ExportFormat.jpeg,
            quality: 90,
            preDecodedRgb: rgb,
            preDecodedWidth: w,
            preDecodedHeight: h,
            captureInfo: _capture,
          ),
        );
        expect(result.success, isTrue, reason: result.error);
        final decoded = img.decodeJpg(await File(dest).readAsBytes())!;
        expect(decoded.width, w);
        expect(decoded.height, h);
        expect(decoded.exif.imageIfd['Make']!.toString(), 'Canon');
        expect(decoded.exif.exifIfd['ISOSpeed']!.toInt(), 400);
        expect(decoded.exif.imageIfd['Software']!.toString(), 'darkmoon');
        // And the sRGB profile rides along in APP2.
        expect(decoded.iccProfile, isNotNull);
        expect(decoded.iccProfile!.data, srgbIccProfile);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
