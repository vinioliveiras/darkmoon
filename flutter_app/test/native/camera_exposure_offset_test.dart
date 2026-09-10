import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/native/edit_source.dart';
import 'package:darkmoon/render/calibration.dart';
import 'package:darkmoon/render/color_space.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The measurement has one job: say how far apart two renderings of the
/// same shot are, in the units the correction will be *spent* in.
///
/// That last clause is the whole file. The answer goes to the Exposure
/// slider, and since 2026-09-10 `applyExposureAndWhiteBalance` multiplies
/// the *linear* light by `2^stops` — so the measurement is a ratio of
/// linear means. (Between 2026-09-09 and 2026-09-10 the stage multiplied
/// the gamma-encoded buffer and this measured in gamma space to match;
/// before that it measured in linear light against the gamma stage and
/// over-corrected by about two, which is what blew the highlights out.
/// The rule survived both: measure in the space you spend in.)
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
          'it; measured in the wrong space this lands 40 levels off',
    );
  });

  /// Stops between two flat encoded values, in linear light.
  double linearStops(int from, int to) =>
      math.log(srgbToLinear(to / 255.0) / srgbToLinear(from / 255.0)) /
      math.ln2;

  test('a brighter preview asks for the linear distance to it', () {
    // 120 -> 160 is 0.42 stops as encoded values and about 0.9 in linear
    // light; within the cap, so the answer is the distance itself.
    expect(
      cameraExposureOffsetStops(flat(120), width, height, jpegOf(flat(160))),
      closeTo(linearStops(120, 160), 0.05),
    );
    expect(linearStops(120, 160), closeTo(0.9, 0.05));
  });

  test('a darker preview asks for the negative of it', () {
    expect(
      cameraExposureOffsetStops(flat(160), width, height, jpegOf(flat(120))),
      closeTo(-linearStops(120, 160), 0.05),
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

  test('it measures linear light, not the encoded values', () {
    // 100 and 150 are a ratio of 1.5 as they stand — 0.585 stops.
    // Linearised they are 0.127 and 0.305, a ratio of 2.4 — 1.26 stops,
    // which is what a linear-light Exposure stage has to be handed to
    // move 100 to 150.
    final stops = cameraExposureOffsetStops(
      flat(100),
      width,
      height,
      jpegOf(flat(150)),
    )!;
    expect(
      stops,
      closeTo(linearStops(100, 150), 0.02),
      reason: 'the encoded ratio would answer 0.585',
    );
    expect(stops, closeTo(1.26, 0.03));
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
