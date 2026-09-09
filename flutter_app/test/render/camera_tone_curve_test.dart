import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

/// Matching the camera's tonality, rather than approximating it with a
/// hand-tuned S-curve.
///
/// A RAW carries the camera's own JPEG of the same shot. [cameraToneCurve]
/// fits a 33-point perceptual curve that maps our decode's tonality onto
/// it, and that curve rides the colour profile's tone slot — which both
/// the CPU and GPU paths already apply, so it needs no render stage of its
/// own and cannot drift between them.
///
/// Measured on real X-T5 frames (2026-09-09), mean absolute error against
/// the camera over the 1st-99th percentiles: 12.5 levels with the
/// hand-tuned [calBaseContrast] S, 0.5 with the fit.
void main() {
  const w = 128;
  const h = 96;

  /// A frame whose luma sweeps the whole range, so a tone curve has
  /// something to act on at every level.
  Uint8List ramp({double Function(double)? through}) {
    final out = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = x / (w - 1);
        if (through != null) v = through(v);
        final b = (v * 255).round().clamp(0, 255);
        final i = (y * w + x) * 3;
        out[i] = out[i + 1] = out[i + 2] = b;
      }
    }
    return out;
  }

  Uint8List jpegOf(Uint8List rgb) {
    final image = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        image.setPixelRgb(x, y, rgb[i], rgb[i + 1], rgb[i + 2]);
      }
    }
    return Uint8List.fromList(img.encodeJpg(image, quality: 100));
  }

  List<double> percentilesOf(Uint8List rgb) {
    final hist = List<int>.filled(256, 0);
    for (var i = 0; i + 2 < rgb.length; i += 3) {
      hist[rgb[i + 1]]++;
    }
    final total = hist.fold<int>(0, (a, b) => a + b);
    return [
      for (final p in const [5, 10, 25, 50, 75, 90, 95])
        () {
          var acc = 0;
          for (var i = 0; i < 256; i++) {
            acc += hist[i];
            if (acc >= total * p / 100.0) return i.toDouble();
          }
          return 255.0;
        }(),
    ];
  }

  ColorProfile profileOf(List<double> tone) => ColorProfile(
    tone: tone,
    hueShift: identityColorProfile.hueShift,
    satMul: identityColorProfile.satMul,
    lumMul: identityColorProfile.lumMul,
  );

  test('the fit reproduces the camera it was measured against', () {
    // The headline, and the only test here that would notice the curve
    // being expressive enough in principle but not as sampled: a
    // 33-point perceptual curve has to carry a real tone mapping.
    final source = ramp();
    final camera = ramp(through: (v) => math.pow(v, 0.62).toDouble());

    final tone = cameraToneCurve(source, w, h, jpegOf(camera));
    expect(tone, isNotNull);

    final rendered = renderRgb(
      w,
      h,
      source,
      RenderParams.fromValues(
        const {},
        baseContrast: 0,
        colorProfile: profileOf(tone!),
      ),
    );

    final got = percentilesOf(rendered);
    final want = percentilesOf(camera);
    var worst = 0.0;
    for (var i = 0; i < got.length; i++) {
      worst = math.max(worst, (got[i] - want[i]).abs());
    }
    expect(
      worst,
      lessThan(6),
      reason:
          'fitted $got against the camera $want — the whole point is that '
          'these are the same photo',
    );
  });

  test('it can only redistribute tonality, never invert it', () {
    // Forced monotone at fit time. A curve that dips would darken
    // something as its input brightened, which is not a tone mapping, it
    // is an artefact.
    final tone = cameraToneCurve(
      ramp(),
      w,
      h,
      jpegOf(ramp(through: (v) => math.pow(v, 1.9).toDouble())),
    )!;
    for (var i = 1; i < tone.length; i++) {
      expect(tone[i], greaterThanOrEqualTo(tone[i - 1]));
    }
    expect(tone.first, greaterThanOrEqualTo(0.0));
    expect(tone.last, lessThanOrEqualTo(1.0));
  });

  test('a decode already matching the camera asks for nothing', () {
    final source = ramp();
    final tone = cameraToneCurve(source, w, h, jpegOf(source))!;
    // Within one control-point step. The curve is sampled at 33 points, so
    // an identity fit can land a whole step off and still be the closest
    // identity this representation can express; asking for tighter would
    // be asking the grid to be finer than it is.
    final step = 1.0 / (colorProfileTonePoints - 1);
    expect(
      _maxDeviation(tone),
      lessThanOrEqualTo(step * 1.01),
      reason: 'a photo the camera and the decode agree on must be left alone',
    );
  });

  test('it refuses exactly what the offset refuses', () {
    // The two are measured from the same pair and the renderer picks one
    // of them, so a photo must never have one without the other.
    final source = ramp();
    for (final embedded in <Uint8List?>[null, jpegOf(ramp())]) {
      expect(
        cameraToneCurve(source, w, h, embedded) == null,
        cameraExposureOffsetStops(source, w, h, embedded) == null,
      );
    }
    // Mismatched shape: a portrait preview against a landscape decode.
    final portrait = img.Image(width: h, height: w);
    final portraitJpeg = Uint8List.fromList(
      img.encodeJpg(portrait, quality: 100),
    );
    expect(cameraToneCurve(source, w, h, portraitJpeg), isNull);
    expect(cameraExposureOffsetStops(source, w, h, portraitJpeg), isNull);
  });
}

double _maxDeviation(List<double> tone) {
  var worst = 0.0;
  for (var i = 0; i < tone.length; i++) {
    worst = math.max(worst, (tone[i] - i / (tone.length - 1)).abs());
  }
  return worst;
}
