import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/native/libraw.dart' show RawMetadata;
import 'package:darkmoon/render/lens_correction.dart';

RawMetadata _metadata({
  String cameraMake = '',
  String cameraModel = '',
  String lensModel = '',
}) => RawMetadata(
  cameraMake: cameraMake,
  cameraModel: cameraModel,
  lensModel: lensModel,
  isoSpeed: 0,
  shutterSeconds: 0,
  apertureFNumber: 0,
  focalLengthMm: 0,
  width: 0,
  height: 0,
);

LensProfile _ptlensProfile({
  required double b,
  String maker = 'Synthco',
  String model = 'Test 24-70mm',
}) => LensProfile(
  maker: maker,
  model: model,
  mount: null,
  cropFactor: 1.0,
  distortionModel: 'ptlens',
  distortion: [LensDistortionPoint(focal: 24, a: 0, b: b, c: 0)],
  vignettingModel: null,
  vignetting: const [],
);

void main() {
  group('applyLensDistortionCorrection', () {
    test('is identity when amount is 0', () {
      final width = 40, height = 40;
      final src = Uint8List(width * height * 3);
      for (var i = 0; i < src.length; i++) {
        src[i] = (i * 7) % 256;
      }
      final profile = _ptlensProfile(b: -0.3);
      final result = applyLensDistortionCorrection(
        src,
        width,
        height,
        profile,
        24,
        0,
      );
      expect(result.width, width);
      expect(result.height, height);
      expect(result.rgbBytes, orderedEquals(src));
    });

    test('barrel-style correction stretches an off-center point outward', () {
      // 140x140: a bright vertical stripe at x=100 (dx=30 from the cx=70
      // center) on an otherwise black row y=70 (dy=0, so the mapping
      // along this row is purely radial in x -- no vertical ambiguity for
      // the peak search below). Parameters (b=-1.5) were chosen, and the
      // expected shift verified, by simulating this exact algorithm in
      // Python: the corrected peak lands at x=108 (dx=38), a clean,
      // full-brightness match well clear of both the original dx=30 and
      // any bilinear-interpolation noise.
      const width = 140;
      const height = 140;
      final src = Uint8List(width * height * 3);
      const stripeX = 100; // dx = 30
      for (var dxOff = -1; dxOff <= 1; dxOff++) {
        final i = (70 * width + (stripeX + dxOff)) * 3;
        src[i] = 255;
        src[i + 1] = 255;
        src[i + 2] = 255;
      }
      // Negative b (like real-world barrel-distorted wide lenses in the
      // bundled DB) means the polynomial factor is < 1 away from center,
      // so a backward-mapped output pixel samples *closer to center* than
      // itself -- equivalently, source content near the edge is stretched
      // further out in the corrected output. See lens_correction.dart's
      // applyLensDistortionCorrection doc comment for the full derivation.
      final profile = _ptlensProfile(b: -1.5);
      final result = applyLensDistortionCorrection(
        src,
        width,
        height,
        profile,
        24,
        1.0,
      );

      // Find the brightest pixel on row y=70 in the corrected output.
      var peakX = 0;
      var peakVal = -1;
      for (var x = 0; x < width; x++) {
        final v = result.rgbBytes[(70 * width + x) * 3];
        if (v > peakVal) {
          peakVal = v;
          peakX = x;
        }
      }
      // The corrected stripe must have moved well further from center
      // (cx=70) than the original dx=30 -- a solid margin, not just past
      // floating-point/bilinear noise.
      expect((peakX - 70).abs(), greaterThanOrEqualTo(35));
    });
  });

  group('applyLensVignetteCorrection', () {
    test('brightens corners more than the center', () {
      const width = 100;
      const height = 100;
      final src = Uint8List(width * height * 3);
      for (var i = 0; i < src.length; i++) {
        src[i] = 128;
      }
      final profile = LensProfile(
        maker: 'Synthco',
        model: 'Test 24-70mm',
        mount: null,
        cropFactor: 1.0,
        distortionModel: null,
        distortion: const [],
        vignettingModel: 'pa',
        vignetting: const [
          LensVignettingPoint(
            focal: 24,
            aperture: 2.8,
            distance: 1000,
            k1: -0.8,
            k2: 0,
            k3: 0,
          ),
        ],
      );
      applyLensVignetteCorrection(src, width, height, profile, 24, 2.8, 1.0);

      final centerVal = src[(50 * width + 50) * 3];
      final cornerVal = src[(2 * width + 2) * 3];
      // Center (dx=dy=0): r=0, falloff=1, exactly untouched.
      expect(centerVal, 128);
      // Corner (2,2): r~0.96 of the half-diagonal, falloff=1-0.8*r^2~0.263,
      // so 128/0.263~487 -> clamped to 255. (Values verified by simulating
      // this exact formula in Python before picking k1.)
      expect(cornerVal, greaterThan(centerVal));
      expect(cornerVal, 255);
    });
  });

  group('matchLensProfile', () {
    test('picks the right profile among several candidates', () {
      final canon2470 = LensProfile(
        maker: 'Canon',
        model: 'Canon EF 24-70mm f/2.8L II USM',
        mount: 'Canon EF',
        cropFactor: 1.0,
        distortionModel: 'ptlens',
        distortion: [const LensDistortionPoint(focal: 24, a: 0, b: 0, c: 0)],
        vignettingModel: null,
        vignetting: const [],
      );
      final canon50 = LensProfile(
        maker: 'Canon',
        model: 'Canon EF 50mm f/1.8 STM',
        mount: 'Canon EF',
        cropFactor: 1.0,
        distortionModel: 'ptlens',
        distortion: [const LensDistortionPoint(focal: 50, a: 0, b: 0, c: 0)],
        vignettingModel: null,
        vignetting: const [],
      );
      final nikon2470 = LensProfile(
        maker: 'Nikon',
        model: 'Nikon AF-S 24-70mm f/2.8E ED VR',
        mount: 'Nikon F',
        cropFactor: 1.0,
        distortionModel: 'ptlens',
        distortion: [const LensDistortionPoint(focal: 24, a: 0, b: 0, c: 0)],
        vignettingModel: null,
        vignetting: const [],
      );
      final profiles = [canon2470, canon50, nikon2470];

      final metadata = _metadata(
        cameraMake: 'Canon',
        cameraModel: 'Canon EOS 5D Mark IV',
        // Real EXIF-style free text: no space before "mm", no maker prefix.
        lensModel: 'EF24-70mm f/2.8L II USM',
      );

      final match = matchLensProfile(profiles, metadata);
      expect(match, same(canon2470));
    });

    test('returns null when nothing scores above the threshold', () {
      final profiles = [
        LensProfile(
          maker: 'Sigma',
          model: 'Sigma 150-600mm f/5-6.3 DG OS HSM',
          mount: null,
          cropFactor: 1.0,
          distortionModel: 'ptlens',
          distortion: [
            const LensDistortionPoint(focal: 150, a: 0, b: 0, c: 0),
          ],
          vignettingModel: null,
          vignetting: const [],
        ),
      ];
      final metadata = _metadata(
        cameraMake: 'Fujifilm',
        lensModel: 'XF 16-55mm f/2.8 R LM WR',
      );
      expect(matchLensProfile(profiles, metadata), isNull);
    });
  });

  group('fixed-lens camera fallback (Fujifilm X100VI bug)', () {
    // Real Lensfun data: fixed-lens bodies are calibrated under a "&
    // compatibles" grouping named after the base model (e.g. the X100VI
    // reuses the X100V's optically-identical entry), and LibRaw reports an
    // empty `lensModel` for these -- there's no interchangeable lens to
    // name. See lens_correction.dart's matchLensProfileByCameraModel doc
    // comment for the full reasoning.
    final x100vProfile = LensProfile(
      maker: 'Fujifilm',
      model: 'X100V & compatibles',
      mount: 'fujix100v2',
      cropFactor: 1.53,
      distortionModel: 'ptlens',
      distortion: [const LensDistortionPoint(focal: 23, a: 0, b: 0, c: 0)],
      vignettingModel: null,
      vignetting: const [],
    );

    test('matchLensProfileByCameraModel matches X100VI to X100V & compatibles',
        () {
      final metadata = _metadata(
        cameraMake: 'Fujifilm',
        cameraModel: 'X100VI',
      );
      expect(
        matchLensProfileByCameraModel([x100vProfile], metadata),
        same(x100vProfile),
      );
    });

    test('resolveLensProfile falls back to camera-model match when '
        'lensModel is empty', () {
      final metadata = _metadata(
        cameraMake: 'Fujifilm',
        cameraModel: 'X100VI',
        lensModel: '',
      );
      final resolved =
          resolveLensProfile([x100vProfile], metadata, null);
      expect(resolved, same(x100vProfile));
    });

    test('does not match a different maker\'s camera body', () {
      final metadata = _metadata(
        cameraMake: 'Sony',
        cameraModel: 'X100VI',
      );
      expect(matchLensProfileByCameraModel([x100vProfile], metadata), isNull);
    });

    test('ignores ordinary interchangeable-lens entries (no "&" in model)',
        () {
      final canon2470 = LensProfile(
        maker: 'Canon',
        model: 'Canon EF 24-70mm f/2.8L II USM',
        mount: 'Canon EF',
        cropFactor: 1.0,
        distortionModel: 'ptlens',
        distortion: [const LensDistortionPoint(focal: 24, a: 0, b: 0, c: 0)],
        vignettingModel: null,
        vignetting: const [],
      );
      final metadata = _metadata(cameraMake: 'Canon', cameraModel: 'EOS R5');
      expect(matchLensProfileByCameraModel([canon2470], metadata), isNull);
    });
  });

  group('applyLensChromaticAberrationCorrection', () {
    LensProfile tcaProfile({required double vr, required double vb}) =>
        LensProfile(
          maker: 'Synthco',
          model: 'Test 24-70mm',
          mount: null,
          cropFactor: 1.0,
          distortionModel: null,
          distortion: const [],
          vignettingModel: null,
          vignetting: const [],
          tcaModel: 'poly3',
          tca: [LensTcaPoint(focal: 24, vr: vr, vb: vb)],
        );

    test('is identity when amount is 0', () {
      const width = 40, height = 40;
      final src = Uint8List(width * height * 3);
      for (var i = 0; i < src.length; i++) {
        src[i] = (i * 5) % 256;
      }
      final result = applyLensChromaticAberrationCorrection(
        src,
        width,
        height,
        tcaProfile(vr: 1.2, vb: 0.8),
        24,
        0,
      );
      expect(result.rgbBytes, orderedEquals(src));
    });

    test('red and blue channels shift oppositely relative to green', () {
      // 100x100, cx=cy=50: a bright stripe at x=80 (dx=30) on row y=50
      // (dy=0, purely radial in x), in all 3 channels. With vr=1.2/vb=0.8
      // and amount=1, the backward-mapping resample pulls each output
      // pixel's red sample from source x = cx + dx*vr and blue from
      // cx + dx*vb -- solving for which OUTPUT x reads the stripe back
      // (source x=80, dx=30) gives peak_red = 50 + 30/1.2 = 75 (pulled
      // toward center) and peak_blue = 50 + 30/0.8 = 87.5 (pushed outward).
      // Green is untouched, so its peak stays exactly at 80.
      const width = 100;
      const height = 100;
      final src = Uint8List(width * height * 3);
      const stripeX = 80;
      for (var dxOff = -1; dxOff <= 1; dxOff++) {
        final i = (50 * width + (stripeX + dxOff)) * 3;
        src[i] = 255;
        src[i + 1] = 255;
        src[i + 2] = 255;
      }
      final result = applyLensChromaticAberrationCorrection(
        src,
        width,
        height,
        tcaProfile(vr: 1.2, vb: 0.8),
        24,
        1.0,
      );

      int peakX(int channel) {
        var peakX = 0;
        var peakVal = -1;
        for (var x = 0; x < width; x++) {
          final v = result.rgbBytes[(50 * width + x) * 3 + channel];
          if (v > peakVal) {
            peakVal = v;
            peakX = x;
          }
        }
        return peakX;
      }

      final redPeak = peakX(0);
      final bluePeak = peakX(2);

      // Green is copied straight through -- the stripe's 3 pixels stay
      // exactly 255, untouched by any resample.
      for (final x in [stripeX - 1, stripeX, stripeX + 1]) {
        expect(result.rgbBytes[(50 * width + x) * 3 + 1], 255);
      }
      // Generous margins clear of both the original dx=30 and bilinear
      // interpolation noise -- red pulled toward center, blue pushed out.
      expect(redPeak, lessThanOrEqualTo(77));
      expect(bluePeak, greaterThanOrEqualTo(84));
      expect(redPeak, lessThan(bluePeak));
    });
  });
}
