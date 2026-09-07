import 'dart:math' as math;
import 'dart:typed_data';

/// Finding *where* the straight lines in a photo are, which is what
/// separates perspective correction from levelling.
///
/// `upright.dart` answers "which way do the edges run" and that is all
/// Level needs. Vertical and the rest need more: converging verticals all
/// run in slightly different directions, and the correction is derived
/// from how that direction changes across the frame. So this one keeps the
/// position axis a plain orientation histogram throws away — a Hough
/// transform, deliberately avoided over there and unavoidable here.
///
/// Lines come back in normal form about the **image centre**, which is
/// where the geometry pipeline rotates and keystones about, so no
/// coordinate shuffling is needed downstream.
class DetectedLine {
  const DetectedLine({
    required this.thetaDeg,
    required this.rho,
    required this.strength,
  });

  /// Direction of the line's normal, degrees in [0, 180).
  final double thetaDeg;

  /// Signed distance from the image centre to the line, in pixels.
  ///
  /// The line is every point where `x*cos(theta) + y*sin(theta) == rho`,
  /// with x and y measured from the centre.
  final double rho;

  /// Accumulated gradient magnitude, normalised so the strongest line in
  /// an image is 1.0.
  final double strength;

  /// Direction the line itself runs, degrees in [0, 180). 0 is horizontal.
  double get angleDeg {
    final angle = (thetaDeg + 90.0) % 180.0;
    return angle < 0 ? angle + 180.0 : angle;
  }

  /// Where this line crosses the horizontal centre line of the image, in
  /// pixels from the centre — or null when it runs too close to
  /// horizontal to cross it usefully.
  ///
  /// This is the position half of "a vertical on the left leans one way
  /// and one on the right leans the other".
  double? get xAtCentre {
    final theta = thetaDeg * math.pi / 180.0;
    final cos = math.cos(theta);
    if (cos.abs() < 1e-6) {
      return null;
    }
    // y = 0 at the centre line, so x*cos(theta) = rho.
    return rho / cos;
  }

  /// Where this line crosses the vertical centre line of the image, in
  /// pixels from the centre — or null when it runs too close to vertical
  /// to cross it usefully. The mirror of [xAtCentre], for the horizontals.
  double? get yAtCentre {
    final theta = thetaDeg * math.pi / 180.0;
    final sin = math.sin(theta);
    if (sin.abs() < 1e-6) {
      return null;
    }
    // x = 0 at the centre line, so y*sin(theta) = rho.
    return rho / sin;
  }

  @override
  String toString() =>
      'DetectedLine(theta=${thetaDeg.toStringAsFixed(1)}, '
      'rho=${rho.toStringAsFixed(1)}, '
      's=${strength.toStringAsFixed(2)})';
}

const double _thetaStepDeg = 1.0;
const int _thetaSteps = 180;
const double _rhoStep = 2.0;

/// Fraction of the strongest gradient below which a pixel does not vote.
const double _edgeFloor = 0.20;

/// How far either side of a pixel's own gradient direction it votes.
///
/// Voting only near the measured normal, instead of across every theta,
/// is what keeps the accumulator sharp: a full sweep smears each edge
/// pixel across the whole table and the peaks come out broad and shifted.
/// The window absorbs the noise in any single pixel's angle.
const int _thetaWindow = 4;

/// The straight lines in [luma], strongest first.
List<DetectedLine> detectLines(
  Uint8List luma,
  int width,
  int height, {
  int maxLines = 24,
  double minStrength = 0.25,
}) {
  if (width < 8 || height < 8) {
    return const [];
  }

  final diagonal = math.sqrt(width * width + height * height.toDouble());
  final rhoSteps = (2 * diagonal / _rhoStep).ceil() + 1;
  final accumulator = Float64List(_thetaSteps * rhoSteps);
  final centreX = width / 2;
  final centreY = height / 2;

  // Same border margin and gradient operator as upright.dart, for the same
  // reasons: a frame-clipped edge leaves a cap along the frame, and
  // Scharr's kernel is the one that does not bias the angle.
  final margin = math.max(2, math.min(width, height) ~/ 100);
  var strongest = 0.0;
  final magnitudes = Float64List(width * height);
  final normals = Float64List(width * height);
  for (var y = margin; y < height - margin; y++) {
    for (var x = margin; x < width - margin; x++) {
      final i = y * width + x;
      final tl = luma[i - width - 1];
      final t = luma[i - width];
      final tr = luma[i - width + 1];
      final l = luma[i - 1];
      final r = luma[i + 1];
      final bl = luma[i + width - 1];
      final b = luma[i + width];
      final br = luma[i + width + 1];

      final gx = 3 * (tr + br) + 10 * r - 3 * (tl + bl) - 10 * l;
      final gy = 3 * (bl + br) + 10 * b - 3 * (tl + tr) - 10 * t;
      magnitudes[i] = math.sqrt(gx * gx + gy * gy);
      if (magnitudes[i] > strongest) {
        strongest = magnitudes[i];
      }
      normals[i] = math.atan2(gy, gx);
    }
  }
  if (strongest <= 0) {
    return const [];
  }

  final floor = strongest * _edgeFloor;
  for (var y = margin; y < height - margin; y++) {
    for (var x = margin; x < width - margin; x++) {
      final i = y * width + x;
      final magnitude = magnitudes[i];
      if (magnitude < floor) {
        continue;
      }
      final dx = x - centreX;
      final dy = y - centreY;
      var normalDeg = normals[i] * 180.0 / math.pi;
      normalDeg %= 180.0;
      if (normalDeg < 0) {
        normalDeg += 180.0;
      }
      final centreBin = (normalDeg / _thetaStepDeg).round();
      for (var d = -_thetaWindow; d <= _thetaWindow; d++) {
        final bin = (centreBin + d + _thetaSteps) % _thetaSteps;
        final theta = bin * _thetaStepDeg * math.pi / 180.0;
        final rho = dx * math.cos(theta) + dy * math.sin(theta);
        final rhoBin = ((rho + diagonal) / _rhoStep).round();
        if (rhoBin < 0 || rhoBin >= rhoSteps) {
          continue;
        }
        accumulator[bin * rhoSteps + rhoBin] += magnitude;
      }
    }
  }

  var peak = 0.0;
  for (final value in accumulator) {
    if (value > peak) {
      peak = value;
    }
  }
  if (peak <= 0) {
    return const [];
  }

  // Non-maximum suppression over a small neighbourhood, so one thick edge
  // yields one line rather than a cluster of near-identical ones.
  const suppressTheta = 3;
  const suppressRho = 4;
  final found = <DetectedLine>[];
  for (var tBin = 0; tBin < _thetaSteps; tBin++) {
    for (var rBin = 0; rBin < rhoSteps; rBin++) {
      final value = accumulator[tBin * rhoSteps + rBin];
      if (value < peak * minStrength) {
        continue;
      }
      var isPeak = true;
      for (var dt = -suppressTheta; dt <= suppressTheta && isPeak; dt++) {
        for (var dr = -suppressRho; dr <= suppressRho; dr++) {
          if (dt == 0 && dr == 0) {
            continue;
          }
          final nr = rBin + dr;
          if (nr < 0 || nr >= rhoSteps) {
            continue;
          }
          final nt = (tBin + dt + _thetaSteps) % _thetaSteps;
          if (accumulator[nt * rhoSteps + nr] > value) {
            isPeak = false;
            break;
          }
        }
      }
      if (!isPeak) {
        continue;
      }
      found.add(
        DetectedLine(
          thetaDeg: tBin * _thetaStepDeg,
          rho: rBin * _rhoStep - diagonal,
          strength: value / peak,
        ),
      );
    }
  }

  found.sort((a, b) => b.strength.compareTo(a.strength));
  return found.length <= maxLines ? found : found.sublist(0, maxLines);
}
