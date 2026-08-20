import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

void main() {
  group('white balance (Temperature/Tint)', () {
    Uint8List flatGray(int width, int height, int value) {
      final buf = Uint8List(width * height * 3);
      buf.fillRange(0, buf.length, value);
      return buf;
    }

    test('neutral temperature (5500K) and tint 0 is an identity', () {
      final src = flatGray(4, 4, 150);
      final out = renderRgb(4, 4, src, const RenderParams());
      for (var i = 0; i < out.length; i++) {
        expect(out[i], 150);
      }
    });

    test('raising temperature above 5500K warms the image (R > B), '
        'matching Lightroom/Camera Raw convention', () {
      final src = flatGray(4, 4, 150);
      final out = renderRgb(4, 4, src, const RenderParams(temperature: 7000));
      expect(out[0], greaterThan(out[2]));
    });

    test('lowering temperature below 5500K cools the image (B > R)', () {
      final src = flatGray(4, 4, 150);
      final out = renderRgb(4, 4, src, const RenderParams(temperature: 4193));
      expect(out[2], greaterThan(out[0]));
    });

    test('a large cool shift (~1300K below neutral) corrects more strongly '
        'than a same-sized warm shift, matching mired (not Kelvin-linear) '
        'perceptual scaling', () {
      final src = flatGray(4, 4, 150);
      final cool = renderRgb(
        4,
        4,
        src,
        const RenderParams(temperature: 4193), // ~1307K below neutral
      );
      final warm = renderRgb(
        4,
        4,
        src,
        const RenderParams(temperature: 6807), // ~1307K above neutral
      );
      final coolShift = (cool[2].toDouble() - cool[0].toDouble()).abs();
      final warmShift = (warm[0].toDouble() - warm[2].toDouble()).abs();
      expect(coolShift, greaterThan(warmShift));
    });

    test('positive tint shifts toward magenta (green down, red/blue up) '
        'without desaturating red/blue asymmetrically, matching Lightroom '
        "convention and this slider's green->magenta gradient", () {
      final src = flatGray(4, 4, 150);
      final out = renderRgb(4, 4, src, const RenderParams(tint: 50));
      expect(out[1], lessThan(150));
      // Red and blue should move together (both up) rather than only
      // green moving in isolation.
      expect(out[0], greaterThan(150));
      expect(out[2], greaterThan(150));
      expect(out[0], out[2]);
    });

    test('tint keeps overall luminance roughly stable', () {
      final src = flatGray(4, 4, 150);
      final out = renderRgb(4, 4, src, const RenderParams(tint: 80));
      final lum = (out[0] + out[1] + out[2]) / 3.0;
      expect(lum, closeTo(150, 6));
    });
  });
}
