import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/colorize.dart';

void main() {
  // A tiny 4x4 gray image — real color decisions don't matter for these
  // tests, only that intensity actually scales the model's a/b prediction.
  Uint8List grayImage(int size, int value) =>
      Uint8List.fromList(List.filled(size * size * 3, value));

  test('intensity 0 leaves the image at its original gray (no model '
      "color makes it through)", () {
    final source = grayImage(4, 128);
    final result = colorizeImage(
      source,
      4,
      4,
      // A model that (unrealistically) predicts strong, non-neutral
      // color everywhere — if intensity 0 doesn't fully suppress it,
      // this test would catch that.
      runModel: (tile) =>
          Float32List.fromList(List.filled(tile.length ~/ 3 * 2, 40.0)),
      modelInputSize: 4,
      intensity: 0.0,
    );
    for (var i = 0; i < result.length; i += 3) {
      // Same gray in, same gray out — a/b forced to 0 means no chroma at
      // all, and L round-trips a neutral gray to within 1 byte of
      // rounding (matches lab_color_test.dart's own tolerance).
      expect(result[i], closeTo(source[i], 2));
      expect(result[i + 1], closeTo(source[i + 1], 2));
      expect(result[i + 2], closeTo(source[i + 2], 2));
    }
  });

  test('intensity 1.0 lets the model\'s predicted color through', () {
    final source = grayImage(4, 128);
    final result = colorizeImage(
      source,
      4,
      4,
      runModel: (tile) =>
          Float32List.fromList(List.filled(tile.length ~/ 3 * 2, 40.0)),
      modelInputSize: 4,
      intensity: 1.0,
    );
    // A positive a/b at this lightness should shift the channels apart —
    // no longer a neutral gray pixel.
    final r = result[0], g = result[1], b = result[2];
    expect(r == g && g == b, isFalse);
  });
}
