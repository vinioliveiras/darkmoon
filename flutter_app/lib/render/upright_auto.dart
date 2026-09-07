import 'dart:math' as math;
import 'dart:typed_data';

import 'calibration.dart';
import 'upright.dart';
import 'upright_lines.dart';

/// Auto mode of PENDING item 27's Upright set: measures a photo and hands
/// back a straighten angle plus the perspective correction that makes its
/// converging edges parallel again.
///
/// The measurement it rests on is a regression, not an average. A single
/// tilted edge tells you nothing about perspective — a whole wall of
/// verticals can be uniformly tilted, which is rotation. What separates
/// the two is how the tilt *changes across the frame*: under a real
/// perspective the verticals fan out from a vanishing point, so a line's
/// tilt varies with where it sits. Fit tilt against position and the
/// slope is the convergence while the intercept absorbs the rotation,
/// which is why this can be measured on the unrotated frame and applied
/// alongside a straighten angle without the two fighting.

/// A straight-line fit of how a family of near-parallel lines fans out.
class ConvergenceFit {
  const ConvergenceFit({
    required this.slope,
    required this.spread,
    required this.count,
    required this.scatter,
  });

  /// Change in the lines' tilt (as a tangent) per pixel of position
  /// across the frame. Zero when they are truly parallel.
  ///
  /// It is the reciprocal of the vanishing point's distance, so it grows
  /// without bound as the perspective gets steeper and is exactly zero
  /// for an orthographic view.
  final double slope;

  /// Distance between the outermost lines in the fit, in pixels.
  ///
  /// A slope fitted across a narrow band of the frame is extrapolation,
  /// and the caller rejects one.
  final double spread;

  final int count;

  /// How far a typical line's tilt sits from the fitted trend, in the same
  /// tangent units as the values themselves.
  ///
  /// This is what tells a family from a coincidence. Three lines always
  /// have a slope through them; whether that slope means anything depends
  /// on whether the rest of the lines agree, and this is that agreement.
  final double scatter;
}

/// Signed tilt away from vertical, degrees in (-90, 90].
double _tiltFromVertical(double angleDeg) {
  var value = (angleDeg - 90.0) % 180.0;
  if (value > 90) {
    value -= 180;
  }
  return value;
}

/// Signed tilt away from horizontal, degrees in (-90, 90].
double _tiltFromHorizontal(double angleDeg) {
  var value = angleDeg % 180.0;
  if (value > 90) {
    value -= 180;
  }
  return value;
}

/// Fits how [lines] fan out — the near-vertical ones when [verticals] is
/// true, the near-horizontal ones otherwise. Null when there is not
/// enough evidence to fit anything.
///
/// The slope is a Theil-Sen estimate: the median of the slope through
/// every pair of lines. An earlier version used least squares with one
/// reweighting pass, on the reasoning that a full robust estimator was
/// more machinery than a handful of lines could justify. That was wrong,
/// and a photograph of a hillside proved it — a terrace of houses climbing
/// a slope puts a dozen genuinely diagonal rooflines through the tilt
/// gate, they are not outliers against the true horizontals but a rival
/// population, and least squares splits the difference between the two.
/// Reweighting cannot help: with that many of them the median residual
/// itself is inflated, so nothing crosses the cutoff. A median of pairwise
/// slopes has no such failure — it ignores a minority outright and, when
/// there are two populations of comparable size, lands on neither rather
/// than between them, which is what [ConvergenceFit.scatter] then reports.
ConvergenceFit? fitConvergence(
  List<DetectedLine> lines, {
  required bool verticals,
}) {
  final positions = <double>[];
  final values = <double>[];
  final weights = <double>[];
  for (final line in lines) {
    final tilt = verticals
        ? _tiltFromVertical(line.angleDeg)
        : _tiltFromHorizontal(line.angleDeg);
    // A line tilted further than this is not a member of the family; it
    // is some other edge in the photo.
    if (tilt.abs() > calUprightMaxTiltDeg) {
      continue;
    }
    final position = verticals ? line.xAtCentre : line.yAtCentre;
    if (position == null) {
      continue;
    }
    positions.add(position);
    values.add(math.tan(tilt * math.pi / 180.0));
    weights.add(line.strength);
  }
  if (positions.length < 3) {
    return null;
  }

  var lowest = double.infinity;
  var highest = -double.infinity;
  for (final position in positions) {
    lowest = math.min(lowest, position);
    highest = math.max(highest, position);
  }
  final spread = highest - lowest;
  if (spread <= 0) {
    return null;
  }

  double median(List<double> of) {
    final sorted = [...of]..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  // Pairs too close together in position divide by almost nothing and
  // return a slope of almost anything, so they are left out rather than
  // allowed to widen the median's tails.
  final minSeparation = spread * calUprightMinPairSeparation;
  final pairSlopes = <double>[];
  for (var i = 0; i < positions.length; i++) {
    for (var j = i + 1; j < positions.length; j++) {
      final run = positions[j] - positions[i];
      if (run.abs() < minSeparation) {
        continue;
      }
      pairSlopes.add((values[j] - values[i]) / run);
    }
  }
  if (pairSlopes.length < 3) {
    return null;
  }

  final slope = median(pairSlopes);
  final intercept = median([
    for (var i = 0; i < positions.length; i++)
      values[i] - slope * positions[i],
  ]);
  final residuals = [
    for (var i = 0; i < positions.length; i++)
      (values[i] - (intercept + slope * positions[i])).abs(),
  ];
  final scatter = median(residuals);

  // Robust first, efficient second. A median of pairwise slopes cannot be
  // dragged by a rival population, which is the whole reason it is here,
  // but with five or six lines it is also throwing away most of what they
  // say — a median steps between discrete pair slopes instead of using
  // all of them. So the robust fit is used for what it is good at, naming
  // which lines belong, and a least-squares fit over just those lines
  // gives the slope. Measured on synthetic perspectives, this halved the
  // scatter in the slider gain it implies.
  final keptPositions = <double>[];
  final keptValues = <double>[];
  final keptWeights = <double>[];
  final cutoff = math.max(scatter * calUprightRefitCutoff, 1e-6);
  for (var i = 0; i < positions.length; i++) {
    if (residuals[i] <= cutoff) {
      keptPositions.add(positions[i]);
      keptValues.add(values[i]);
      keptWeights.add(weights[i]);
    }
  }

  var refined = slope;
  if (keptPositions.length >= 4) {
    var sw = 0.0;
    var sx = 0.0;
    var sy = 0.0;
    var sxx = 0.0;
    var sxy = 0.0;
    for (var i = 0; i < keptPositions.length; i++) {
      final w = keptWeights[i];
      sw += w;
      sx += w * keptPositions[i];
      sy += w * keptValues[i];
      sxx += w * keptPositions[i] * keptPositions[i];
      sxy += w * keptPositions[i] * keptValues[i];
    }
    final denominator = sxx - sx * sx / sw;
    if (sw > 0 && denominator.abs() > 1e-9) {
      refined = (sxy - sx * sy / sw) / denominator;
    }
  }

  return ConvergenceFit(
    slope: refined,
    spread: spread,
    count: positions.length,
    scatter: scatter,
  );
}

/// What Auto found: the straighten angle and keystone corrections to
/// apply, in the same units as the Transform sliders.
class UprightCorrection {
  const UprightCorrection({
    required this.straightenAngle,
    required this.vertical,
    required this.horizontal,
  });

  final double straightenAngle;
  final double vertical;
  final double horizontal;

  bool get isEmpty => straightenAngle == 0 && vertical == 0 && horizontal == 0;

  @override
  String toString() =>
      'UprightCorrection(straighten=${straightenAngle.toStringAsFixed(2)}, '
      'vertical=${vertical.toStringAsFixed(1)}, '
      'horizontal=${horizontal.toStringAsFixed(1)})';
}

/// Turns a fitted convergence into a Transform slider value, or 0 when
/// the fit does not earn one.
double _correctionFrom(
  ConvergenceFit? fit,
  double extent,
  double gain, {
  double gainSlope = 0,
}) {
  if (fit == null || fit.spread < extent * calUprightMinSpread) {
    return 0;
  }
  // Three lines are enough to have a slope and not enough to know whether
  // it means anything.
  if (fit.count < calUprightMinLines) {
    return 0;
  }
  // The slope is per pixel, so scaling by the frame's own extent is what
  // makes the number mean the same thing on a preview and on a full-size
  // frame. Without it Auto would correct a downscaled photo harder than
  // the same photo at full resolution.
  final fanOut = fit.slope * extent;
  // The trend has to be bigger than the disagreement about it. Without
  // this the fit always answers, and on a photo whose edges are not a
  // family at all it answers with noise — which is how a straight-on
  // façade came back asking for 26 units of horizontal keystone.
  if (fanOut.abs() < fit.scatter * calUprightMinAgreement) {
    return 0;
  }
  // The gain is not constant: the geometry pass anchors the bottom edge,
  // so a steep perspective needs proportionally more slider than a gentle
  // one. See calUprightVerticalGainSlope.
  final correction = fanOut * (gain + gainSlope * fanOut.abs());
  if (correction.abs() < calUprightDeadZone) {
    return 0;
  }
  return correction.clamp(-100.0, 100.0);
}

/// Both axes as the geometry measures them, before Auto decides which of
/// them it is willing to act on.
///
/// Separate from [uprightAutoFor] because the two questions are
/// different: this one is "what do the edges say", which is a matter of
/// measurement, and Auto's is "which of that can be believed", which is a
/// matter of judgement. The Vertical and Full modes still to come will
/// want the measurement without Auto's judgement.
UprightCorrection? uprightMeasureFor(Uint8List luma, int width, int height) {
  if (width < 32 || height < 32) {
    return null;
  }
  final lines = detectLines(
    luma,
    width,
    height,
    maxLines: calUprightMaxLines.round(),
    minStrength: calUprightLineFloor,
  );
  if (lines.isEmpty) {
    return null;
  }

  final vertical = _correctionFrom(
    fitConvergence(lines, verticals: true),
    width.toDouble(),
    calUprightVerticalGain,
    gainSlope: calUprightVerticalGainSlope,
  );
  final horizontal = _correctionFrom(
    fitConvergence(lines, verticals: false),
    height.toDouble(),
    calUprightHorizontalGain,
  );
  // Straighten comes from the orientation estimator rather than these
  // lines: it pools every edge in the frame instead of the handful that
  // survive peak-picking, which makes it markedly steadier on the small
  // angles that matter for levelling. See upright.dart.
  final straighten = levelRotationFor(luma, width, height) ?? 0.0;

  return UprightCorrection(
    straightenAngle: straighten,
    vertical: vertical,
    horizontal: horizontal,
  );
}

/// Measures [luma] and returns the Upright Auto correction, or null when
/// the photo holds nothing straight enough to go on.
///
/// **Auto never applies the horizontal axis**, and that is a deliberate
/// retreat from an earlier version that did.
///
/// The two axes are not equally trustworthy, because the world is not
/// symmetric. A building's verticals are vertical by construction, so
/// verticals that fan out across a frame are nearly always perspective.
/// Horizontals are not like that at all: hillsides, rooflines climbing a
/// slope, riverbanks and shorelines are all genuinely tilted, and a
/// terrace of houses up a hill puts a whole population of them in the
/// frame with the level water below.
///
/// The trap is that such a photo does not merely confuse the measurement,
/// it satisfies it. Roofs high in the frame, water low, tilt varying
/// smoothly between them: that is a textbook converging family, and it
/// was measured fitting one with a scatter of 0.018 against a fan-out of
/// 0.63 — better agreement than a real, mild perspective manages. No
/// threshold on strength, count, spread or agreement separates the two,
/// because as geometry they are the same thing. Only knowing that one set
/// of edges is a roof and the other is a wall would, and lines carry no
/// such thing.
///
/// So the choice is which way to be wrong. A photo needing horizontal
/// keystone is uncommon; a photo containing something sloped is not. Auto
/// declining to touch it costs the rare case a slider drag, and applying
/// it costs the common case a visibly skewed photo — which is exactly
/// what a straight-on façade with a hill behind it got: 26 units of
/// horizontal keystone it did not want.
///
/// The measurement stays, tested and calibrated, in [uprightMeasureFor].
UprightCorrection? uprightAutoFor(Uint8List luma, int width, int height) {
  final measured = uprightMeasureFor(luma, width, height);
  if (measured == null) {
    return null;
  }
  final correction = UprightCorrection(
    straightenAngle: measured.straightenAngle,
    vertical: measured.vertical,
    horizontal: 0,
  );
  return correction.isEmpty ? null : correction;
}

/// A photo's luma handed across an isolate boundary, for [uprightAutoFor].
class UprightAutoRequest {
  const UprightAutoRequest(this.luma, this.width, this.height);

  final Uint8List luma;
  final int width;
  final int height;
}

/// `compute()` entry point — the per-pixel work here is the same class as
/// a render and has no business on the UI isolate.
UprightCorrection? uprightAutoForRequest(UprightAutoRequest request) =>
    uprightAutoFor(request.luma, request.width, request.height);
