import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/upright.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic images with a known tilt, because there is no other way to
/// know whether this measures what it claims to. A detector that is
/// confidently a degree and a half out looks exactly like one that works.
void main() {
  const width = 320;
  const height = 240;

  /// A dark frame with bright straight bands drawn at [angleDeg].
  ///
  /// Anti-aliased, and that is not cosmetic. Drawn with a hard threshold,
  /// a band at 3 degrees is a staircase: long horizontal runs with
  /// occasional one-pixel steps. Sobel reads that as a horizontal edge,
  /// because that is genuinely what it is, and the detector correctly
  /// reported 0 degrees for it. Real photographs have a soft ramp across
  /// an edge whose gradient carries the true angle, so the test image has
  /// to as well or it is testing rasterisation rather than detection.
  Uint8List frameWithEdgesAt(
    List<double> angles, {
    double thickness = 3.0,
    double ramp = 1.5,
  }) {
    final luma = Uint8List(width * height);
    for (final angleDeg in angles) {
      final radians = angleDeg * math.pi / 180.0;
      // Normal of the line: distance from the centre along it is what
      // decides how much of the band covers a pixel.
      final nx = -math.sin(radians);
      final ny = math.cos(radians);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final dx = x - width / 2;
          final dy = y - height / 2;
          final distance = (dx * nx + dy * ny).abs();
          // The ramp either side. 1.5px by default, which is about the
          // sharpest a real edge gets after a lens and a Bayer demosaic —
          // and deliberately the hard case, since a softer edge carries
          // more angular information per pixel and is measured better.
          final coverage = ((thickness + ramp - distance) / ramp).clamp(
            0.0,
            1.0,
          );
          final value = (coverage * 255).round();
          final i = y * width + x;
          if (value > luma[i]) {
            luma[i] = value;
          }
        }
      }
    }
    return luma;
  }

  group('levelRotationFor', () {
    test('returns the rotation that undoes the tilt', () {
      for (final tilt in [2.0, 6.0, -9.0]) {
        final rotation = levelRotationFor(
          frameWithEdgesAt([tilt]),
          width,
          height,
        );
        expect(rotation, isNotNull, reason: 'no rotation offered at $tilt');
        expect(
          rotation!,
          // 0.35 is the worst case for the razor-sharp 1.5px ramp this
          // helper draws, and it is a property of the input rather than of
          // the estimator: the softer the edge, the more angular
          // information each pixel carries. Measured errors at 11 degrees
          // are 0.30 with a 1.5px ramp, 0.19 at 3px and 0.09 at 6px, and a
          // real photo after demosaic sits at the soft end. The test keeps
          // the hard case because that is the one that can go wrong.
          closeTo(-tilt, 0.35),
          reason: 'levelling $tilt should rotate back by ${-tilt}',
        );
      }
    });

    test('declines a photo whose only edges are genuinely diagonal', () {
      // A 30-degree edge is a roof or a road, not a crooked horizon.
      // Rotating to level it would tilt the photo, not fix it.
      final rotation = levelRotationFor(
        frameWithEdgesAt([30.0]),
        width,
        height,
      );
      expect(rotation, isNull);
    });

    test('declines a frame with nothing in it', () {
      expect(
        levelRotationFor(Uint8List(width * height), width, height),
        isNull,
      );
    });

    test('both axes agree, so a rotated grid levels by the same amount', () {
      final rotation = levelRotationFor(
        frameWithEdgesAt([5.0, 95.0]),
        width,
        height,
      );
      expect(rotation, isNotNull);
      expect(
        rotation!,
        closeTo(-5.0, 0.25),
        reason:
            'verticals and horizontals disagree about which axis they '
            'belong to but agree exactly about the camera rotation',
      );
    });
  });

  group('accuracy against edge sharpness', () {
    test('a softly-ramped edge is measured to within a tenth of a degree', () {
      // Guards the gradient operator. Sobel was measurably biased here — a
      // consistent 4.7% underestimate at every angle — and Scharr replaced
      // it precisely because angle is the only thing this computes. A
      // regression to a less isotropic kernel would show up as this
      // loosening.
      final rotation = levelRotationFor(
        frameWithEdgesAt([11.0], ramp: 6.0),
        width,
        height,
      );
      expect(rotation, isNotNull);
      expect(rotation!, closeTo(-11.0, 0.12));
    });
  });

  group('deviationFromAxis', () {
    test('folds every axis onto the same signed answer', () {
      expect(deviationFromAxis(0), closeTo(0, 1e-9));
      expect(deviationFromAxis(3), closeTo(3, 1e-9));
      expect(deviationFromAxis(93), closeTo(3, 1e-9));
      expect(deviationFromAxis(177), closeTo(-3, 1e-9));
      expect(deviationFromAxis(87), closeTo(-3, 1e-9));
    });
  });

  group('rgbToLuma', () {
    test('uses the pipeline weights', () {
      final rgb = Uint8List.fromList([255, 0, 0, 0, 255, 0, 0, 0, 255]);
      final luma = rgbToLuma(rgb, 3, 1);
      expect(luma[0], (0.2126 * 255).round());
      expect(luma[1], (0.7152 * 255).round());
      expect(luma[2], (0.0722 * 255).round());
    });
  });
}
