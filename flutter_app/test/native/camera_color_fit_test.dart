import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/render/color_profile.dart';
import 'package:darkmoon/render/color_space.dart';
import 'package:darkmoon/render/hsl.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colour fit recovers a per-hue rendering applied to a frame: the
/// bins it touched come back with the multipliers, the others near
/// identity, and a frame that is not the same picture is refused.
void main() {
  const width = 240, height = 160;

  /// A colourful frame: hue sweeps along x, saturation along y, over a
  /// brightness gradient — every hue bin gets many blocks.
  Uint8List frame() {
    final rgb = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final hue = 360.0 * x / width;
        final sat = 0.25 + 0.6 * y / height;
        final val = 0.35 + 0.4 * ((x + y) % 40) / 40;
        final (r, g, b) = hsvToRgb(hue, sat, val);
        final i = (y * width + x) * 3;
        rgb[i] = (linearToSrgb(r) * 255).round().clamp(0, 255);
        rgb[i + 1] = (linearToSrgb(g) * 255).round().clamp(0, 255);
        rgb[i + 2] = (linearToSrgb(b) * 255).round().clamp(0, 255);
      }
    }
    return rgb;
  }

  /// [rgb] with the camera's rendering applied: blues (around 240°) more
  /// saturated, reds (around 0°) rotated toward orange, greens darker.
  Uint8List rendered(Uint8List rgb) {
    final out = Uint8List(rgb.length);
    for (var i = 0; i < rgb.length; i += 3) {
      var (h, s, v) = rgbToHsv(
        srgbToLinear(rgb[i] / 255.0),
        srgbToLinear(rgb[i + 1] / 255.0),
        srgbToLinear(rgb[i + 2] / 255.0),
      );
      final blue = math.exp(-math.pow((h - 240) / 25, 2));
      final red = math.exp(-math.pow(((h + 180) % 360 - 180) / 25, 2));
      final green = math.exp(-math.pow((h - 120) / 25, 2));
      s = (s * (1 + 0.4 * blue)).clamp(0.0, 1.0);
      h = (h + 8 * red) % 360;
      v = v * (1 - 0.2 * green);
      final (r, g, b) = hsvToRgb(h, s, v);
      out[i] = (linearToSrgb(r) * 255).round().clamp(0, 255);
      out[i + 1] = (linearToSrgb(g) * 255).round().clamp(0, 255);
      out[i + 2] = (linearToSrgb(b) * 255).round().clamp(0, 255);
    }
    return out;
  }

  int bin(double hue) => (hue / (360 / colorProfileBins)).floor();

  test('recovers the per-hue rendering the camera applied', () {
    final ours = frame();
    final camera = rendered(ours);
    final fit = cameraColorFit(ours, width, height, camera, width, height)!;
    expect(fit.satMul[bin(240)], closeTo(1.4, 0.12));
    expect(fit.satMul[bin(60)], closeTo(1.0, 0.08));
    expect(fit.hueShift[bin(0)], closeTo(8, 3));
    expect(fit.hueShift[bin(180)].abs(), lessThan(3));
    expect(fit.lumMul[bin(120)], closeTo(0.8, 0.08));
    expect(fit.lumMul[bin(300)], closeTo(1.0, 0.06));
  });

  test('the same frame fits to identity', () {
    final ours = frame();
    final fit = cameraColorFit(ours, width, height, ours, width, height)!;
    for (var i = 0; i < colorProfileBins; i++) {
      expect(fit.satMul[i], closeTo(1.0, 0.02));
      expect(fit.lumMul[i], closeTo(1.0, 0.02));
      expect(fit.hueShift[i].abs(), lessThan(1));
    }
  });

  test('a frame that is not the same picture is refused', () {
    final ours = frame();
    // The camera frame flipped: block brightness no longer tracks.
    final flipped = Uint8List(ours.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final src = (y * width + x) * 3;
        final dst = ((height - 1 - y) * width + (width - 1 - x)) * 3;
        flipped[dst] = ours[src];
        flipped[dst + 1] = ours[src + 1];
        flipped[dst + 2] = ours[src + 2];
      }
    }
    expect(cameraColorFit(ours, width, height, flipped, width, height), isNull);
  });

  test(
    'the fit survives the trip through JSON, and an old entry re-measures',
    () {
      final ours = frame();
      final match = CameraMatch(
        tone: [for (var i = 0; i < colorProfileTonePoints; i++) i / 32],
        color: cameraColorFit(
          ours,
          width,
          height,
          rendered(ours),
          width,
          height,
        ),
      );
      final back = CameraMatch.fromJson(match.toJson())!;
      expect(back.color!.satMul, match.color!.satMul);
      expect(back.color!.hueShift, match.color!.hueShift);
      expect(
        CameraMatch.fromJson({'stops': 0.1, 'tone': match.tone}),
        isNull,
        reason: 'an entry without a colour field predates the fit',
      );
      final noColor = CameraMatch.fromJson({
        'stops': 0.1,
        'tone': match.tone,
        'color': null,
      })!;
      expect(noColor.color, isNull);
    },
  );
}
