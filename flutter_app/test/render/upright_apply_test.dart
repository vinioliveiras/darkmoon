import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/crop_transform.dart';
import 'package:darkmoon/render/upright.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ties the measurement to the thing that acts on it.
///
/// levelRotationFor returns "the rotation that would level this", and
/// CropTransformParams.straightenAngle takes a rotation — but nothing
/// guarantees the two agree about which way is positive, and reading the
/// sampling code to work it out is exactly how a sign error survives.
/// Rotating the wrong way looks identical to rotating the right way until
/// someone tries it on a crooked photo.
///
/// So: tilt a synthetic frame, ask for the correction, apply it through
/// the real geometry pipeline, and measure what is left.
void main() {
  const width = 256;
  const height = 256;

  /// A frame of bright bands at [angleDeg], softly ramped so each pixel
  /// carries real angular information.
  Uint8List tiltedFrame(double angleDeg) {
    final rgb = Uint8List(width * height * 3);
    final radians = angleDeg * math.pi / 180.0;
    final nx = -math.sin(radians);
    final ny = math.cos(radians);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dx = x - width / 2;
        final dy = y - height / 2;
        final along = dx * nx + dy * ny;
        // A repeating set of bands, so the frame stays covered after it is
        // rotated and the measurement has something to work with
        // everywhere.
        final phase = (along % 48).abs();
        final distance = math.min(phase, 48 - phase);
        final coverage = ((6.0 - distance) / 6.0).clamp(0.0, 1.0);
        final value = (coverage * 255).round();
        final i = (y * width + x) * 3;
        rgb[i] = value;
        rgb[i + 1] = value;
        rgb[i + 2] = value;
      }
    }
    return rgb;
  }

  double? tiltOf(Uint8List rgb, int w, int h) =>
      levelRotationFor(rgbToLuma(rgb, w, h), w, h);

  test('the correction is applied in the direction that removes the tilt', () {
    for (final tilt in [4.0, -6.0]) {
      final source = tiltedFrame(tilt);

      final before = tiltOf(source, width, height);
      expect(before, isNotNull, reason: 'nothing measurable at $tilt');
      expect(
        before!,
        closeTo(-tilt, 0.4),
        reason: 'the frame should read as needing ${-tilt}',
      );

      final corrected = applyCropTransform(
        source,
        width,
        height,
        CropTransformParams(straightenAngle: before),
      );

      final after = tiltOf(
        corrected.rgbBytes,
        corrected.width,
        corrected.height,
      );
      expect(after, isNotNull, reason: 'nothing measurable after correcting');
      expect(
        after!.abs(),
        lessThan(before.abs() / 3),
        reason:
            'applying $before to a frame tilted by $tilt left ${after.abs()} '
            'degrees, which is not a correction — if it is roughly twice '
            'the original tilt, the sign is inverted',
      );
    }
  });

  test('a frame that is already level is left alone', () {
    final level = tiltedFrame(0);
    final rotation = tiltOf(level, width, height);
    expect(rotation, isNotNull);
    expect(
      rotation!.abs(),
      lessThan(0.25),
      reason: 'a level frame must not be nudged',
    );
  });
}
