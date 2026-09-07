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
    // is some other edge in the photo, and letting it into the fit drags
    // the slope toward whatever it happens to be doing.
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

  ({double slope, double intercept})? solve(List<double> w) {
    var sw = 0.0;
    var sx = 0.0;
    var sy = 0.0;
    var sxx = 0.0;
    var sxy = 0.0;
    for (var i = 0; i < positions.length; i++) {
      final weight = w[i];
      sw += weight;
      sx += weight * positions[i];
      sy += weight * values[i];
      sxx += weight * positions[i] * positions[i];
      sxy += weight * positions[i] * values[i];
    }
    if (sw <= 0) {
      return null;
    }
    final denominator = sxx - sx * sx / sw;
    if (denominator.abs() < 1e-9) {
      return null;
    }
    final slope = (sxy - sx * sy / sw) / denominator;
    return (slope: slope, intercept: (sy - slope * sx) / sw);
  }

  var fit = solve(weights);
  if (fit == null) {
    return null;
  }

  // One reweighting pass. A photo usually holds a few strong edges that
  // belong to no family at all — a diagonal roof, a guy wire — and they
  // pass the tilt gate while sitting far off the trend. Dropping whatever
  // the first fit could not explain is enough to be rid of them; a full
  // robust regression is more machinery than the handful of lines here
  // can justify.
  final residuals = <double>[
    for (var i = 0; i < positions.length; i++)
      (values[i] - (fit.intercept + fit.slope * positions[i])).abs(),
  ];
  final sorted = [...residuals]..sort();
  final median = sorted[sorted.length ~/ 2];
  if (median > 0) {
    final kept = <double>[
      for (var i = 0; i < positions.length; i++)
        residuals[i] > median * calUprightOutlierCutoff ? 0.0 : weights[i],
    ];
    if (kept.where((w) => w > 0).length >= 3) {
      fit = solve(kept) ?? fit;
    }
  }

  var lowest = double.infinity;
  var highest = -double.infinity;
  for (final position in positions) {
    lowest = math.min(lowest, position);
    highest = math.max(highest, position);
  }
  return ConvergenceFit(
    slope: fit.slope,
    spread: highest - lowest,
    count: positions.length,
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
double _correctionFrom(ConvergenceFit? fit, double extent, double gain) {
  if (fit == null || fit.spread < extent * calUprightMinSpread) {
    return 0;
  }
  // The slope is per pixel, so scaling by the frame's own extent is what
  // makes the number mean the same thing on a preview and on a full-size
  // frame. Without it Auto would correct a downscaled photo harder than
  // the same photo at full resolution.
  final correction = fit.slope * extent * gain;
  if (correction.abs() < calUprightDeadZone) {
    return 0;
  }
  return correction.clamp(-100.0, 100.0);
}

/// Measures [luma] and returns the Upright Auto correction, or null when
/// the photo holds nothing straight enough to go on.
UprightCorrection? uprightAutoFor(Uint8List luma, int width, int height) {
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

  final correction = UprightCorrection(
    straightenAngle: straighten,
    vertical: vertical,
    horizontal: horizontal,
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
