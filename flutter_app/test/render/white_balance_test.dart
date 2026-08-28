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

    test('the Von Kries model is luminance-neutral — a Tint move barely '
        'shifts overall brightness', () {
      final src = flatGray(4, 4, 150);
      for (final tint in [-60.0, -20.0, 40.0, 90.0]) {
        final out = renderRgb(4, 4, src, RenderParams(tint: tint));
        final lum = 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2];
        expect(lum, closeTo(150, 8), reason: 'tint $tint');
      }
    });

    test('preserveTintBrightness is a harmless no-op now (model already '
        'luminance-normalised)', () {
      final src = flatGray(4, 4, 150);
      final off = renderRgb(4, 4, src, const RenderParams(tint: 40));
      final on = renderRgb(
        4,
        4,
        src,
        const RenderParams(tint: 40, preserveTintBrightness: true),
      );
      for (var i = 0; i < off.length; i++) {
        expect(on[i], off[i]);
      }
    });

    test('per-photo as-shot reference: sliders parked at the camera value '
        'are an identity, and 5500/0 now shifts', () {
      final src = flatGray(4, 4, 150);
      // A photo whose camera as-shot was 5200 K / +6.
      final atAsShot = renderRgb(
        4,
        4,
        src,
        const RenderParams(
          temperature: 5200,
          tint: 6,
          asShotKelvin: 5200,
          asShotTint: 6,
        ),
      );
      for (final v in atAsShot) {
        expect(v, 150);
      }
      final at5500 = renderRgb(
        4,
        4,
        src,
        const RenderParams(
          temperature: 5500,
          tint: 0,
          asShotKelvin: 5200,
          asShotTint: 6,
        ),
      );
      // 5500 > the 5200 as-shot reference -> a warming correction: R
      // ends up above B (and above where it sat at the as-shot no-op).
      expect(at5500[0], greaterThan(at5500[2]));
      expect(at5500[0], greaterThan(150));
    });
  });
}
