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

/// How close in direction two lines must be to be the same edge seen
/// twice. Generous, because the refinement moves near-peaks apart.
const double _dedupeAngleDeg = 3.0;

/// How close in position, as a fraction of the frame's diagonal, with a
/// floor of a few pixels so it stays sane on a small frame.
const double _dedupeRhoFraction = 0.012;

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
        _refine(
          DetectedLine(
            thetaDeg: tBin * _thetaStepDeg,
            rho: rBin * _rhoStep - diagonal,
            strength: value / peak,
          ),
          magnitudes,
          normals,
          width,
          height,
          centreX,
          centreY,
          margin,
          floor,
        ),
      );
    }
  }

  found.sort((a, b) => b.strength.compareTo(a.strength));

  // One edge, one line. Suppressing non-maxima in the accumulator is not
  // enough on its own: a long, tilted edge spreads its votes across many
  // rho bins for each theta, so it comes back two or three times over,
  // and refining those near-peaks lands them a couple of pixels and a
  // degree or two apart rather than on top of each other.
  //
  // Those copies are worse than redundant. They agree with each other at
  // an angle that is slightly wrong, so a fit sees a tight little cluster
  // vouching for it — five detections of one edge outvoting the four
  // real ones beside it. Measured on a synthetic perspective: nine lines
  // returned for five drawn, and the fan-out they implied came out a
  // third short.
  final kept = <DetectedLine>[];
  final rhoTolerance = math.max(6.0, diagonal * _dedupeRhoFraction);
  for (final line in found) {
    var duplicate = false;
    for (final earlier in kept) {
      var angle = (line.thetaDeg - earlier.thetaDeg).abs() % 180.0;
      if (angle > 90) {
        angle = 180 - angle;
      }
      if (angle <= _dedupeAngleDeg &&
          (line.rho - earlier.rho).abs() <= rhoTolerance) {
        duplicate = true;
        break;
      }
    }
    if (!duplicate) {
      kept.add(line);
    }
    if (kept.length >= maxLines) {
      break;
    }
  }
  return kept;
}

/// How far either side of a peak's line the refinement looks for the
/// pixels that made it.
const double _refineRadius = 3.0;

/// How far a pixel's own gradient may point away from the line's normal
/// and still be counted as belonging to it. Keeps the refinement from
/// walking onto a crossing edge that happens to pass through the band.
const double _refineNormalToleranceDeg = 20.0;

/// Re-measures [line] from the pixels that voted for it, replacing the
/// accumulator's answer with a continuous one.
///
/// The accumulator is quantised: one degree of angle, two pixels of
/// position. For finding lines that is ample. For measuring how a family
/// of them fans out it is not remotely enough — a gentle perspective
/// spreads its verticals over about five degrees in total, so a one-degree
/// step throws away most of the signal and what survives is noise. It
/// showed up as a slider gain that should have been one number coming back
/// anywhere between 133 and 377 depending on the frame, and as a weaker
/// perspective measuring *stronger* than a sharper one.
///
/// So each peak is re-fitted to its own pixels by principal axis: the
/// weighted covariance of their positions, whose major axis is the
/// direction they actually lie along, to whatever precision the pixels
/// support. The scan is bounded to a band around the line rather than
/// sweeping the frame, so this costs a few thousand pixels per line.
DetectedLine _refine(
  DetectedLine line,
  Float64List magnitudes,
  Float64List normals,
  int width,
  int height,
  double centreX,
  double centreY,
  int margin,
  double floor,
) {
  final theta = line.thetaDeg * math.pi / 180.0;
  final cos = math.cos(theta);
  final sin = math.sin(theta);
  final tolerance = _refineNormalToleranceDeg * math.pi / 180.0;

  var sw = 0.0;
  var sx = 0.0;
  var sy = 0.0;
  var sxx = 0.0;
  var syy = 0.0;
  var sxy = 0.0;

  void consider(int x, int y) {
    if (x < margin ||
        y < margin ||
        x >= width - margin ||
        y >= height - margin) {
      return;
    }
    final i = y * width + x;
    final magnitude = magnitudes[i];
    if (magnitude < floor) {
      return;
    }
    // The pixel's gradient has to agree with the line's normal, modulo
    // 180 — an edge is the same edge whichever side is brighter.
    var delta = (normals[i] - theta).abs() % math.pi;
    if (delta > math.pi / 2) {
      delta = math.pi - delta;
    }
    if (delta > tolerance) {
      return;
    }
    final dx = x - centreX;
    final dy = y - centreY;
    sw += magnitude;
    sx += magnitude * dx;
    sy += magnitude * dy;
    sxx += magnitude * dx * dx;
    syy += magnitude * dy * dy;
    sxy += magnitude * dx * dy;
  }

  // Walk along the line's own long axis, scanning only the band either
  // side of it.
  final radius = _refineRadius.ceil();
  if (cos.abs() >= sin.abs()) {
    // Normal is mostly horizontal, so the line is mostly vertical: one
    // sample column per row.
    for (var y = 0; y < height; y++) {
      final dy = y - centreY;
      final centre = (line.rho - dy * sin) / cos + centreX;
      final from = (centre - radius).floor();
      final to = (centre + radius).ceil();
      for (var x = from; x <= to; x++) {
        consider(x, y);
      }
    }
  } else {
    for (var x = 0; x < width; x++) {
      final dx = x - centreX;
      final centre = (line.rho - dx * cos) / sin + centreY;
      final from = (centre - radius).floor();
      final to = (centre + radius).ceil();
      for (var y = from; y <= to; y++) {
        consider(x, y);
      }
    }
  }

  if (sw <= 0) {
    return line;
  }
  final meanX = sx / sw;
  final meanY = sy / sw;
  final varX = sxx / sw - meanX * meanX;
  final varY = syy / sw - meanY * meanY;
  final covXY = sxy / sw - meanX * meanY;
  // Major axis of the covariance: the direction the pixels lie along.
  // Degenerate when they form a blob rather than a line, in which case
  // the accumulator's answer is as good as anything.
  final spread = math.sqrt((varX - varY) * (varX - varY) + 4 * covXY * covXY);
  if (spread < 1e-9) {
    return line;
  }
  final axis = 0.5 * math.atan2(2 * covXY, varX - varY);
  var refinedTheta = (axis * 180.0 / math.pi + 90.0) % 180.0;
  if (refinedTheta < 0) {
    refinedTheta += 180.0;
  }
  final refinedRadians = refinedTheta * math.pi / 180.0;
  return DetectedLine(
    thetaDeg: refinedTheta,
    rho: meanX * math.cos(refinedRadians) + meanY * math.sin(refinedRadians),
    strength: line.strength,
  );
}
