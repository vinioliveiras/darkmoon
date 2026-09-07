import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/render/calibration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The measurement has one job: say how many stops apart two renderings
/// of the same shot are. So the tests build a pair that is a *known*
/// number of stops apart and check the answer, rather than pinning
/// whatever the code happens to return.
void main() {
  const width = 64;
  const height = 48;

  double toSrgb(double linear) => linear <= 0.0031308
      ? linear * 12.92
      : 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;

  /// A frame whose linear luminance is [linear] everywhere, encoded to
  /// sRGB the way a decode's output is.
  Uint8List flat(double linear) {
    final byte = (toSrgb(linear.clamp(0.0, 1.0)) * 255).round().clamp(0, 255);
    return Uint8List(width * height * 3)..fillRange(0, width * height * 3, byte);
  }

  Uint8List jpegOf(Uint8List rgb, {int w = width, int h = height}) {
    final image = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        image.setPixelRgb(x, y, rgb[i], rgb[i + 1], rgb[i + 2]);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 100));
  }

  test('a preview one stop brighter asks for one stop', () {
    final decoded = flat(0.09);
    final preview = jpegOf(flat(0.18));
    expect(
      cameraExposureOffsetStops(decoded, width, height, preview),
      closeTo(1.0, 0.1),
    );
  });

  test('a preview one stop darker asks for minus one', () {
    final decoded = flat(0.18);
    final preview = jpegOf(flat(0.09));
    expect(
      cameraExposureOffsetStops(decoded, width, height, preview),
      closeTo(-1.0, 0.1),
    );
  });

  test('a matching preview asks for nothing', () {
    final decoded = flat(0.18);
    final preview = jpegOf(flat(0.18));
    expect(
      cameraExposureOffsetStops(decoded, width, height, preview)!.abs(),
      lessThan(0.1),
    );
  });

  test('the answer is capped', () {
    // Four stops apart. Beyond the cap the comparison is likelier to be
    // wrong than the decode is, so it is clamped rather than trusted.
    final decoded = flat(0.02);
    final preview = jpegOf(flat(0.32));
    expect(
      cameraExposureOffsetStops(decoded, width, height, preview),
      calCameraExposureLimitStops,
    );
  });

  test('no preview, no answer', () {
    expect(cameraExposureOffsetStops(flat(0.18), width, height, null), isNull);
  });

  test('a preview of a different shape is refused', () {
    // A portrait thumbnail against a landscape decode: the means of two
    // differently-oriented crops are not comparable, and an answer here
    // would be a guess dressed as a measurement.
    final preview = jpegOf(
      Uint8List(48 * 64 * 3)..fillRange(0, 48 * 64 * 3, 200),
      w: 48,
      h: 64,
    );
    expect(
      cameraExposureOffsetStops(flat(0.18), width, height, preview),
      isNull,
    );
  });

  test('two nearly black frames are refused', () {
    // A ratio of two almost-zero means is noise with no upper bound, and
    // a dark photo is where a wrong answer would show most.
    final decoded = flat(0.0002);
    final preview = jpegOf(flat(0.0004));
    expect(
      cameraExposureOffsetStops(decoded, width, height, preview),
      isNull,
    );
  });

  test('it measures in linear light, not in the encoded values', () {
    // The distinction is the whole reason for the sRGB table. Encoded,
    // 0.09 and 0.18 linear sit at about 0.35 and 0.46 — a ratio of 1.34,
    // which as a power of two would read as 0.4 stops rather than 1.0.
    final decoded = flat(0.09);
    final preview = jpegOf(flat(0.18));
    final stops = cameraExposureOffsetStops(decoded, width, height, preview)!;
    expect(
      stops,
      greaterThan(0.8),
      reason: 'averaging the gamma-encoded values would answer about 0.4',
    );
  });
}
