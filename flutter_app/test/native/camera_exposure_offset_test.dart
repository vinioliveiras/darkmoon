import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/native/edit_source.dart';
import 'package:darkmoon/render/calibration.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The measurement has one job: say how far apart two renderings of the
/// same shot are, in the units the correction will be *spent* in.
///
/// That last clause is the whole file. The answer goes to the Exposure
/// slider, and `_applyExposure` multiplies the gamma-encoded buffer by
/// `2^(units / calExposureUnitsPerStop)`. Until 2026-09-09 this measured
/// in linear light instead, on the reasoning that exposure is a
/// multiplication there — true of exposure in general, not true of this
/// pipeline's Exposure stage. The two disagree by roughly a factor of two,
/// always in the direction of over-correcting, and that is what blew the
/// highlights out.
///
/// So the tests build a pair a *known* distance apart and check the
/// answer, and then check that spending the answer actually lands.
void main() {
  const width = 64;
  const height = 48;

  /// A flat 8-bit frame — the encoding a decode's output is already in.
  Uint8List flat(int byte, {int w = width, int h = height}) =>
      Uint8List(w * h * 3)..fillRange(0, w * h * 3, byte);

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

  test('spending the offset lands the render on the camera brightness', () {
    // The headline. Nothing else here would catch an offset that is
    // internally consistent but unspendable through the knob it is for.
    const decoded = 100;
    const camera = 150;
    final source = flat(decoded);

    final stops = cameraExposureOffsetStops(
      source,
      width,
      height,
      jpegOf(flat(camera)),
    );
    expect(stops, isNotNull);

    final rendered = renderRgb(
      width,
      height,
      source,
      RenderParams.fromValues(
        const {},
        baseContrast: 0,
        baseExposureStops: stops!,
      ),
    );
    expect(
      rendered[0],
      closeTo(camera, 2),
      reason:
          'the correction exists to put the decode where the camera put '
          'it; measured in linear light this overshoots to about 190',
    );
  });

  test('a preview one stop brighter asks for one stop', () {
    expect(
      cameraExposureOffsetStops(flat(90), width, height, jpegOf(flat(180))),
      closeTo(1.0, 0.05),
    );
  });

  test('a preview one stop darker asks for minus one', () {
    expect(
      cameraExposureOffsetStops(flat(180), width, height, jpegOf(flat(90))),
      closeTo(-1.0, 0.05),
    );
  });

  test('a matching preview asks for nothing', () {
    expect(
      cameraExposureOffsetStops(
        flat(120),
        width,
        height,
        jpegOf(flat(120)),
      )!.abs(),
      lessThan(0.05),
    );
  });

  test('it measures the encoded values, not linear light', () {
    // The inverse of the assertion this file used to carry, and the
    // reason the sRGB table it used to build is gone. 100 and 150 are a
    // ratio of 1.5 as they stand — 0.585 stops. Linearised they are 0.127
    // and 0.305, a ratio of 2.4, which would read as 1.26 stops and be
    // spent as more than twice the correction the knob delivers.
    final stops = cameraExposureOffsetStops(
      flat(100),
      width,
      height,
      jpegOf(flat(150)),
    )!;
    expect(
      stops,
      closeTo(math.log(150 / 100) / math.ln2, 0.02),
      reason: 'linearising the means would answer about 1.26',
    );
  });

  test('the answer is capped', () {
    // Beyond the cap the comparison is likelier to be wrong than the
    // decode is, so it is clamped rather than trusted.
    expect(
      cameraExposureOffsetStops(flat(8), width, height, jpegOf(flat(250))),
      calCameraExposureLimitStops,
    );
  });

  test('no preview, no answer', () {
    expect(cameraExposureOffsetStops(flat(120), width, height, null), isNull);
  });

  test('a preview of a different shape is refused', () {
    // A portrait thumbnail against a landscape decode: the means of two
    // differently-oriented crops are not comparable, and an answer here
    // would be a guess dressed as a measurement.
    expect(
      cameraExposureOffsetStops(
        flat(120),
        width,
        height,
        jpegOf(flat(200, w: 48, h: 64), w: 48, h: 64),
      ),
      isNull,
    );
  });

  test('two nearly black frames are refused', () {
    // A ratio of two almost-zero means is noise with no upper bound, and
    // a dark photo is where a wrong answer would show most.
    expect(
      cameraExposureOffsetStops(flat(1), width, height, jpegOf(flat(2))),
      isNull,
    );
  });

  group('a pair that came back from a cache', () {
    EditSourcePair cached(Uint8List rgb) => EditSourcePair(
      preview: EditSource(width: width, height: height, rgbBytes: rgb),
      live: EditSource(width: width, height: height, rgbBytes: rgb),
    );

    test('carries no offset of its own', () {
      // Not a wish — the reason [probeCameraMatch] has to exist. A
      // cache hit skips decodeRawImage, the only place the match is ever
      // measured, so the photo would render at LibRaw's auto-brightened
      // exposure with nothing pulling it back. Every open after the first
      // blew out (2026-09-09).
      final cachedPair = decodeEditSourcePairFromCachedJpeg(jpegOf(flat(120)));
      expect(cachedPair?.baseExposureStops, isNull);
      expect(cachedPair?.baseToneCurve, isNull);
    });

    test('the probe answers what a fresh decode would have', () {
      final source = flat(100);
      final embedded = jpegOf(flat(150));
      final repaired = cached(source).withCameraMatch(
        probeCameraMatch((
          source: EditSource(width: width, height: height, rgbBytes: source),
          embeddedJpeg: embedded,
        )),
      );
      expect(
        repaired.baseExposureStops,
        closeTo(
          cameraExposureOffsetStops(source, width, height, embedded)!,
          1e-9,
        ),
      );
      expect(
        repaired.baseToneCurve,
        cameraToneCurve(source, width, height, embedded),
      );
    });

    test('withCameraMatch leaves the pixels alone', () {
      final pair = cached(flat(77));
      final next = pair.withCameraMatch(const CameraMatch(stops: 0.5));
      expect(next.preview.rgbBytes, pair.preview.rgbBytes);
      expect(next.live.rgbBytes, pair.live.rgbBytes);
      expect(next.baseExposureStops, 0.5);
    });
  });
}
