import 'dart:typed_data';

import 'package:darkmoon/render/inpaint.dart';
import 'package:flutter_test/flutter_test.dart';

/// The geometry around the model: where the hole is, which window the
/// model is shown, and how its answer comes back — only inside the
/// brush's coverage, faded by the coverage's edge.
void main() {
  const width = 64, height = 48;

  Uint8List gradient() {
    final rgb = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 3;
        rgb[i] = x * 4;
        rgb[i + 1] = y * 5;
        rgb[i + 2] = 90;
      }
    }
    return rgb;
  }

  /// A 10x10 hole at (20..29, 15..24), with a three-pixel half-covered
  /// ring around it: the brush's soft edge.
  Float32List hole() {
    final alpha = Float32List(width * height);
    for (var y = 12; y <= 27; y++) {
      for (var x = 17; x <= 32; x++) {
        final inside = x >= 20 && x <= 29 && y >= 15 && y <= 24;
        alpha[y * width + x] = inside ? 1.0 : 0.5;
      }
    }
    return alpha;
  }

  /// Paints the hole flat 200 and hands everything else back unchanged.
  Float32List flatFill(Float32List image, Float32List mask) {
    final n = mask.length;
    final out = Float32List(image.length);
    for (var i = 0; i < n; i++) {
      for (var c = 0; c < 3; c++) {
        out[c * n + i] = mask[i] > 0.5 ? 200 : image[c * n + i] * 255;
      }
    }
    return out;
  }

  test('finds the covered rows and columns', () {
    // The soft edge counts: it is part of what the model paints.
    expect(maskBounds(hole(), width, height), (
      left: 17,
      top: 12,
      right: 32,
      bottom: 27,
    ));
    expect(maskBounds(hole(), width, height, threshold: 0.6), (
      left: 20,
      top: 15,
      right: 29,
      bottom: 24,
    ));
    expect(maskBounds(Float32List(width * height), width, height), isNull);
  });

  test('nothing covered, nothing changes', () {
    final rgb = gradient();
    var called = false;
    final out = inpaintRegion(
      rgb,
      width,
      height,
      Float32List(width * height),
      runModel: (image, mask) {
        called = true;
        return image;
      },
    );
    expect(called, isFalse);
    expect(identical(out, rgb), isTrue);
  });

  test(
    'the model sees a window with the hole marked, and only the hole is repainted',
    () {
      final rgb = gradient();
      Float32List? seenMask;
      final out = inpaintRegion(
        rgb,
        width,
        height,
        hole(),
        runModel: (image, mask) {
          seenMask = mask;
          return flatFill(image, mask);
        },
        modelSize: 64,
      );
      // The hole is a minority of the window, and present.
      final ones = seenMask!.where((v) => v == 1.0).length;
      expect(ones, greaterThan(0));
      expect(ones, lessThan(seenMask!.length ~/ 2));

      // Inside: the model's flat fill (bilinear resampling smears a pixel
      // or two at the very edge, so judge the centre).
      final centre = (20 * width + 25) * 3;
      expect(out[centre], closeTo(200, 3));
      expect(out[centre + 1], closeTo(200, 3));
      // The half-covered ring: the model painted it too, and it lands
      // half way between the original and the fill.
      final ring = (13 * width + 25) * 3;
      final original = rgb[ring].toDouble();
      expect(out[ring], closeTo((original + 200) / 2, 12));
      // Untouched outside the brush: byte for byte.
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          if (x >= 17 && x <= 32 && y >= 12 && y <= 27) {
            continue;
          }
          final i = (y * width + x) * 3;
          expect(out[i], rgb[i], reason: 'pixel ($x,$y) red');
          expect(out[i + 1], rgb[i + 1], reason: 'pixel ($x,$y) green');
          expect(out[i + 2], rgb[i + 2], reason: 'pixel ($x,$y) blue');
        }
      }
      // The input is left alone.
      expect(rgb[centre], 25 * 4);
    },
  );

  test('a hole near the edge keeps the window inside the photo', () {
    final rgb = gradient();
    final alpha = Float32List(width * height);
    for (var y = 0; y < 6; y++) {
      for (var x = 0; x < 6; x++) {
        alpha[y * width + x] = 1.0;
      }
    }
    final out = inpaintRegion(
      rgb,
      width,
      height,
      alpha,
      runModel: flatFill,
      modelSize: 16,
      minMargin: 100,
    );
    expect(out[(2 * width + 2) * 3], closeTo(200, 3));
    expect(out[(40 * width + 60) * 3], rgb[(40 * width + 60) * 3]);
  });
}
