import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/library/negative_converter.dart';
import 'package:darkmoon/render/negative.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// A colour negative as a JPEG: bright scene on the right, dark on the
/// left, under an orange mask.
Uint8List _negativeJpeg(int w, int h) {
  final im = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final neg = 1 - x / (w - 1);
      im.setPixelRgb(
        x,
        y,
        (40 + neg * 200).round(),
        (25 + neg * 170).round(),
        (15 + neg * 120).round(),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  test('the preview base shrinks the photo and measures its bounds', () {
    final base = decodeNegativePreviewBase((
      jpeg: _negativeJpeg(1200, 400),
      maxDim: 600,
    ))!;
    expect(base.width, 600);
    expect(base.height, 200);
    expect(base.rgb.length, 600 * 200 * 3);
    for (var c = 0; c < 3; c++) {
      expect(base.bounds.max[c], greaterThan(base.bounds.min[c]));
    }
    expect(
      decodeNegativePreviewBase((jpeg: Uint8List(10), maxDim: 600)),
      isNull,
    );
  });

  test('the preview inverts, and the compare state shows the original', () {
    final base = decodeNegativePreviewBase((
      jpeg: _negativeJpeg(300, 100),
      maxDim: 300,
    ))!;
    final positive = renderNegativePreviewRgba((
      base: base,
      params: const NegativeParams(enabled: true),
    ));
    final original = renderNegativePreviewRgba((
      base: base,
      params: const NegativeParams(enabled: false),
    ));
    int lumaAt(Uint8List rgba, int x) {
      final i = (50 * 300 + x) * 4;
      return (0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2])
          .round();
    }

    expect(lumaAt(positive, 5), lessThan(lumaAt(positive, 294)));
    expect(lumaAt(original, 5), greaterThan(lumaAt(original, 294)));
    expect(original[3], 255);
  });

  test('a file converts to a TIFF beside it, numbered when taken', () {
    final dir = Directory.systemTemp.createTempSync('darkmoon_negative');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = p.join(dir.path, 'roll_07.jpg');
    File(source).writeAsBytesSync(_negativeJpeg(240, 160));

    final out = convertNegativeFile((
      path: source,
      params: const NegativeParams(enabled: true, exposure: 0.2),
    ));
    expect(p.basename(out), 'roll_07_Positive.tiff');
    final tiff = img.decodeTiff(File(out).readAsBytesSync())!;
    expect(tiff.width, 240);
    expect(tiff.height, 160);
    // Inverted: the negative is bright on the left (dark scene) and dark
    // on the right (bright scene), so the positive is the other way round.
    final left = tiff.getPixel(3, 80), right = tiff.getPixel(236, 80);
    expect(right.g, greaterThan(left.g));
    expect(right.g, greaterThan(200));

    final again = convertNegativeFile((
      path: source,
      params: const NegativeParams(enabled: true),
    ));
    expect(p.basename(again), 'roll_07_Positive (2).tiff');
    expect(
      () => convertNegativeFile((
        path: p.join(dir.path, 'missing.jpg'),
        params: const NegativeParams(enabled: true),
      )),
      throwsA(anything),
    );
  });
}
