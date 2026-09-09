import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:darkmoon/native/camera_match.dart';
import 'package:darkmoon/render/color_profile.dart';

/// [measureCameraMatch] is the form the app actually calls, and the two
/// separate functions are what the app used to call. They have to agree.
///
/// The split exists for speed, not for behaviour: taken separately the two
/// measurements decode the camera's JPEG twice and walk both images twice,
/// which was 2.1 seconds of a 2.5-second warm open on a 13 MP embedded
/// preview (measured 2026-09-09). A faster path that quietly answers
/// something else is worse than the slow one.
void main() {
  const w = 96;
  const h = 64;

  Uint8List gradient({double gamma = 1.0}) {
    final out = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = (x / (w - 1));
        final b = (math.pow(v, gamma) * 255).round().clamp(0, 255);
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

  test('it answers exactly what the two separate calls answer', () {
    final source = gradient();
    final camera = jpegOf(gradient(gamma: 0.6));

    final combined = measureCameraMatch(source, w, h, camera);
    expect(
      combined.stops,
      cameraExposureOffsetStops(source, w, h, camera),
      reason: 'the offset must not shift just because it shares a pass',
    );
    expect(
      combined.tone,
      cameraToneCurve(source, w, h, camera),
      reason: 'nor the curve',
    );
    expect(combined.isEmpty, isFalse);
  });

  test('it refuses together, the way the separate calls refuse', () {
    // The renderer picks one of the two, so a result carrying only one
    // would leave which correction applies depending on measurement order.
    final source = gradient();
    for (final embedded in <Uint8List?>[null, Uint8List(0)]) {
      final match = measureCameraMatch(source, w, h, embedded);
      expect(match.isEmpty, isTrue);
      expect(match.stops, isNull);
      expect(match.tone, isNull);
    }
  });

  group('persisted between sessions', () {
    test('a measurement survives the round trip intact', () {
      // It is written once per file and read on every open after that, so
      // a lossy trip would quietly restyle every photo already measured.
      final match = measureCameraMatch(
        gradient(),
        w,
        h,
        jpegOf(gradient(gamma: 0.6)),
      );
      final restored = CameraMatch.fromJson(
        jsonDecode(jsonEncode(match.toJson())),
      )!;
      expect(restored.stops, match.stops);
      expect(restored.tone, match.tone);
    });

    test('a damaged entry reads as "not measured", not as a wrong curve', () {
      // A curve of the wrong length would be applied without complaint,
      // and a half-written cache entry is the ordinary way to get one.
      expect(CameraMatch.fromJson(null), isNull);
      expect(CameraMatch.fromJson('nonsense'), isNull);
      expect(CameraMatch.fromJson(const {'stops': 0.5}), isNull);
      expect(
        CameraMatch.fromJson(const {
          'stops': 0.5,
          'tone': [0.0, 0.5, 1.0],
        }),
        isNull,
        reason:
            'three points where the profile slot takes '
            '$colorProfileTonePoints',
      );
    });

    test('a match with no offset but a real curve still round-trips', () {
      // stops is nullable on its own — the curve is what the renderer
      // spends, and dropping it because the offset was absent would undo
      // the whole match.
      final tone = [
        for (var i = 0; i < colorProfileTonePoints; i++)
          i / (colorProfileTonePoints - 1),
      ];
      final restored = CameraMatch.fromJson(
        jsonDecode(jsonEncode(CameraMatch(tone: tone).toJson())),
      )!;
      expect(restored.stops, isNull);
      expect(restored.tone, tone);
    });
  });
}
