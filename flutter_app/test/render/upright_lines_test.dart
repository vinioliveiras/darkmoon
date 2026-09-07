import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/upright_lines.dart';
import 'package:flutter_test/flutter_test.dart';

/// The point of this detector, as against upright.dart's, is that it knows
/// *where* each line is. So the tests check position as well as direction:
/// a detector that finds the right angles at the wrong places would pass a
/// direction-only check and then produce nonsense vanishing points.
void main() {
  const width = 256;
  const height = 256;

  /// Draws softly-ramped bright lines. [lines] are (angleDeg, offset)
  /// where offset is the signed distance from the image centre along the
  /// line's own normal — the same convention DetectedLine.rho uses.
  Uint8List frameWith(List<(double, double)> lines) {
    final luma = Uint8List(width * height);
    for (final (angleDeg, offset) in lines) {
      final radians = angleDeg * math.pi / 180.0;
      // The normal of a line running at angleDeg points at angleDeg - 90,
      // which is the direction DetectedLine.thetaDeg names. Getting this
      // backwards drew every line mirrored about the centre while the
      // detector reported it correctly — the failure looked like a
      // detector bug and was not.
      final nx = math.sin(radians);
      final ny = -math.cos(radians);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final dx = x - width / 2;
          final dy = y - height / 2;
          final distance = (dx * nx + dy * ny - offset).abs();
          final coverage = ((3.0 + 3.0 - distance) / 3.0).clamp(0.0, 1.0);
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

  /// The detected line closest to [angleDeg] in direction.
  DetectedLine? nearest(List<DetectedLine> lines, double angleDeg) {
    DetectedLine? best;
    var bestDelta = double.infinity;
    for (final line in lines) {
      var delta = (line.angleDeg - angleDeg).abs() % 180.0;
      if (delta > 90) {
        delta = 180 - delta;
      }
      if (delta < bestDelta) {
        bestDelta = delta;
        best = line;
      }
    }
    return best;
  }

  test('finds a vertical line and says where it is', () {
    // A vertical line 40px right of centre.
    final lines = detectLines(frameWith([(90.0, 40.0)]), width, height);
    expect(lines, isNotEmpty);

    final vertical = nearest(lines, 90.0)!;
    expect(vertical.angleDeg, closeTo(90.0, 2.0));
    expect(
      vertical.xAtCentre,
      closeTo(40.0, 6.0),
      reason: 'direction alone is not enough — the position is the point',
    );
  });

  test('separates two verticals at different positions', () {
    final lines = detectLines(
      frameWith([(90.0, -60.0), (90.0, 60.0)]),
      width,
      height,
    );
    final xs =
        lines
            .where((l) => (l.angleDeg - 90).abs() < 5)
            .map((l) => l.xAtCentre!)
            .toList()
          ..sort();
    expect(
      xs.length,
      greaterThanOrEqualTo(2),
      reason: 'two lines 120px apart must not merge into one',
    );
    expect(xs.first, closeTo(-60.0, 6.0));
    expect(xs.last, closeTo(60.0, 6.0));
  });

  test('a converging pair leans in opposite directions', () {
    // What a photo of a building taken looking up actually gives: the
    // left vertical leans right, the right one leans left.
    final lines = detectLines(
      frameWith([(84.0, -55.0), (96.0, 55.0)]),
      width,
      height,
    );
    final left = lines
        .where((l) => (l.xAtCentre ?? 0) < -20 && (l.angleDeg - 90).abs() < 15)
        .toList();
    final right = lines
        .where((l) => (l.xAtCentre ?? 0) > 20 && (l.angleDeg - 90).abs() < 15)
        .toList();
    expect(left, isNotEmpty, reason: 'no line found on the left');
    expect(right, isNotEmpty, reason: 'no line found on the right');
    expect(
      left.first.angleDeg,
      lessThan(right.first.angleDeg),
      reason:
          'the two must lean opposite ways, which is what convergence '
          'means and what the correction is derived from',
    );
  });

  test('finds a horizontal line', () {
    final lines = detectLines(frameWith([(0.0, -30.0)]), width, height);
    final horizontal = nearest(lines, 0.0)!;
    expect(deviation(horizontal.angleDeg), closeTo(0.0, 2.0));
  });

  test('an empty frame yields nothing', () {
    expect(detectLines(Uint8List(width * height), width, height), isEmpty);
  });

  test('strength is normalised with the strongest at one', () {
    final lines = detectLines(frameWith([(90.0, 0.0)]), width, height);
    expect(lines.first.strength, closeTo(1.0, 1e-9));
    for (final line in lines) {
      expect(line.strength, lessThanOrEqualTo(1.0));
    }
  });
}

/// Signed distance from horizontal, in (-90, 90].
double deviation(double angleDeg) {
  var value = angleDeg % 180.0;
  if (value > 90) {
    value -= 180;
  }
  return value;
}
