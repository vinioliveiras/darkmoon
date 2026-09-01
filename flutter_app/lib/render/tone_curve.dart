import 'dart:math' as math;
import 'dart:typed_data';

/// A single draggable control point on the tone curve, normalized to
/// 0..1 on both axes — (0,0) is pure black in/out, (1,1) is pure white
/// in/out, matching Meridian's Tone Curve panel.
class CurvePoint {
  const CurvePoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is CurvePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// The default curve: a straight diagonal (output == input) — a no-op,
/// matching every other adjustment's "0/default means unchanged"
/// convention.
const identityToneCurve = [CurvePoint(0, 0), CurvePoint(1, 1)];

bool isIdentityToneCurve(List<CurvePoint> points) {
  if (points.length != identityToneCurve.length) {
    return false;
  }
  for (var i = 0; i < points.length; i++) {
    if (points[i] != identityToneCurve[i]) {
      return false;
    }
  }
  return true;
}

/// Builds a 256-entry 0-255 -> 0-255 lookup table from [points] (assumed
/// already sorted by x) using the same monotone cubic Hermite spline as
/// Solstice's `apply_curve` (a Fritsch-Carlson-style construction: each
/// point's tangent is the average of its neighboring secant slopes,
/// zeroed at a local extremum and rescaled if it would overshoot), for a
/// smooth curve rather than sharp linear segments.
///
/// This replaced a plain Catmull-Rom spline, which (unlike this one) can
/// overshoot past its control points' y-range and — for `identityToneCurve`
/// specifically — didn't reduce to a true straight line: with the first/
/// last point's neighbor duplicated (Catmull-Rom's usual way of handling a
/// spline's ends), it evaluated to a visible S-curve (~0.203 at t=0.25
/// instead of 0.25) even for two collinear points.
Uint8List buildToneCurveLut(List<CurvePoint> points) {
  final lut = Uint8List(256);
  if (points.length < 2) {
    for (var i = 0; i < 256; i++) {
      lut[i] = i;
    }
    return lut;
  }
  for (var i = 0; i < 256; i++) {
    final y = _evaluateCurve(points, i / 255.0);
    lut[i] = (y * 255.0).clamp(0.0, 255.0).round();
  }
  return lut;
}

double _evaluateCurve(List<CurvePoint> points, double x) {
  if (x <= points.first.x) {
    return points.first.y;
  }
  if (x >= points.last.x) {
    return points.last.y;
  }
  final lastIndex = points.length - 1;
  for (var i = 0; i < lastIndex; i++) {
    final p1 = points[i];
    final p2 = points[i + 1];
    if (x > p2.x) {
      continue;
    }
    final p0 = points[math.max(0, i - 1)];
    final p3 = points[math.min(lastIndex, i + 2)];
    final deltaBefore = (p1.y - p0.y) / math.max(0.001, p1.x - p0.x);
    final deltaCurrent = (p2.y - p1.y) / math.max(0.001, p2.x - p1.x);
    final deltaAfter = (p3.y - p2.y) / math.max(0.001, p3.x - p2.x);
    var tangentAtP1 = i == 0
        ? deltaCurrent
        : (deltaBefore * deltaCurrent <= 0
            ? 0.0
            : (deltaBefore + deltaCurrent) / 2.0);
    var tangentAtP2 = i + 1 == lastIndex
        ? deltaCurrent
        : (deltaCurrent * deltaAfter <= 0
            ? 0.0
            : (deltaCurrent + deltaAfter) / 2.0);
    if (deltaCurrent != 0) {
      final alpha = tangentAtP1 / deltaCurrent;
      final beta = tangentAtP2 / deltaCurrent;
      final magnitudeSq = alpha * alpha + beta * beta;
      if (magnitudeSq > 9.0) {
        final tau = 3.0 / math.sqrt(magnitudeSq);
        tangentAtP1 *= tau;
        tangentAtP2 *= tau;
      }
    }
    return _interpolateCubicHermite(x, p1, p2, tangentAtP1, tangentAtP2)
        .clamp(0.0, 1.0);
  }
  return points.last.y;
}

double _interpolateCubicHermite(
  double x,
  CurvePoint p1,
  CurvePoint p2,
  double m1,
  double m2,
) {
  final dx = p2.x - p1.x;
  if (dx <= 0) {
    return p1.y;
  }
  final t = (x - p1.x) / dx;
  final t2 = t * t;
  final t3 = t2 * t;
  final h00 = 2 * t3 - 3 * t2 + 1;
  final h10 = t3 - 2 * t2 + t;
  final h01 = -2 * t3 + 3 * t2;
  final h11 = t3 - t2;
  return h00 * p1.y + h10 * m1 * dx + h01 * p2.y + h11 * m2 * dx;
}

/// Applies the curve to every channel of packed RGB [img] in place — a
/// no-op for the identity curve, matching every other adjustment. Used
/// for the master Tone Curve (affects R, G and B identically).
///
/// Designed to run via `compute()`: pure function over simple,
/// isolate-transferable data (same as the rest of render.dart).
void applyToneCurve(Float32List img, List<CurvePoint> points) {
  _applyCurveToChannel(img, null, points);
}

/// Applies independent curves to the R, G and B channels — used for the
/// Color Curve panel. Each channel is skipped individually when its own
/// curve is the identity, so e.g. a red-only tweak costs nothing on G/B.
void applyColorCurves(
  Float32List img,
  List<CurvePoint> red,
  List<CurvePoint> green,
  List<CurvePoint> blue,
) {
  _applyCurveToChannel(img, 0, red);
  _applyCurveToChannel(img, 1, green);
  _applyCurveToChannel(img, 2, blue);
}

/// Applies [points] to [img] — every channel when [channelOffset] is null
/// (the master Tone Curve), or just one interleaved channel (0=R, 1=G,
/// 2=B) otherwise.
void _applyCurveToChannel(
  Float32List img,
  int? channelOffset,
  List<CurvePoint> points,
) {
  if (isIdentityToneCurve(points)) {
    return;
  }
  final sorted = [...points]..sort((a, b) => a.x.compareTo(b.x));
  final lut = buildToneCurveLut(sorted);
  final step = channelOffset == null ? 1 : 3;
  for (var i = channelOffset ?? 0; i < img.length; i += step) {
    final v = img[i].clamp(0.0, 255.0).round();
    img[i] = lut[v].toDouble();
  }
}

double _tanh(double v) {
  final e = math.exp(2.0 * v);
  return (e - 1.0) / (e + 1.0);
}

/// Meridian's *parametric* Tone Curve — four region sliders (Shadows /
/// Darks / Lights / Highlights, each -100..100) whose extents are set by
/// three split points (defaults 25 / 50 / 75). Unlike the point curve, the
/// user never places points directly; the region sliders bend a fixed
/// 7-node curve. Applied on top of (before) the point Tone Curve, matching
/// Meridian, where both sub-panels feed the same result.
///
/// The node layout and the `tanh`-based response are ported from Solstice's
/// `buildParametricPoints` (Curves.tsx) — same spline family as
/// [buildToneCurveLut] evaluates.
class ParametricCurve {
  const ParametricCurve({
    this.shadows = 0,
    this.darks = 0,
    this.lights = 0,
    this.highlights = 0,
    this.shadowSplit = 25,
    this.midtoneSplit = 50,
    this.highlightSplit = 75,
  });

  /// From the editor's flat `{sliderName: value}` map — keys
  /// `ParamCurve<Shadows|Darks|Lights|Highlights>` and
  /// `ParamCurve<Shadow|Midtone|Highlight>Split`.
  factory ParametricCurve.fromValues(Map<String, double> values) {
    const d = ParametricCurve();
    return ParametricCurve(
      shadows: values['ParamCurveShadows'] ?? d.shadows,
      darks: values['ParamCurveDarks'] ?? d.darks,
      lights: values['ParamCurveLights'] ?? d.lights,
      highlights: values['ParamCurveHighlights'] ?? d.highlights,
      shadowSplit: values['ParamCurveShadowSplit'] ?? d.shadowSplit,
      midtoneSplit: values['ParamCurveMidtoneSplit'] ?? d.midtoneSplit,
      highlightSplit: values['ParamCurveHighlightSplit'] ?? d.highlightSplit,
    );
  }

  final double shadows;
  final double darks;
  final double lights;
  final double highlights;
  final double shadowSplit;
  final double midtoneSplit;
  final double highlightSplit;

  bool get isIdentity =>
      shadows == 0 && darks == 0 && lights == 0 && highlights == 0;
}

const identityParametricCurve = ParametricCurve();

/// The 7 control points the four region sliders bend into shape — feed
/// straight to [buildToneCurveLut] / [applyToneCurve]. Returns
/// [identityToneCurve] when nothing is dialed in.
List<CurvePoint> parametricCurvePoints(ParametricCurve p) {
  if (p.isIdentity) {
    return identityToneCurve;
  }
  final vS = p.shadows / 100.0;
  final vD = p.darks / 100.0;
  final vL = p.lights / 100.0;
  final vH = p.highlights / 100.0;

  final s1 = (p.shadowSplit / 100.0).clamp(0.05, 0.90);
  final s2 = (p.midtoneSplit / 100.0).clamp(s1 + 0.02, 0.94);
  final s3 = (p.highlightSplit / 100.0).clamp(s2 + 0.02, 0.98);

  final xS = s1 / 2.0;
  final xH = (s3 + 1.0) / 2.0;
  final xs = [0.0, xS, s1, s2, s3, xH, 1.0];

  const sliderGain = 1.2;
  const maxDisplacement = 0.35;
  double response(double v, double x) {
    final headroom = (v >= 0 ? 1.0 - x : x).clamp(0.0, 1.0);
    return _tanh(v * sliderGain) * maxDisplacement * math.sqrt(headroom);
  }

  final ys = [
    0.0,
    xS + response(vS, xS),
    s1 + (response(vS, s1) + response(vD, s1)) / 2.0,
    s2 + (response(vD, s2) + response(vL, s2)) / 2.0,
    s3 + (response(vL, s3) + response(vH, s3)) / 2.0,
    xH + response(vH, xH),
    1.0,
  ];

  return [
    for (var i = 0; i < 7; i++)
      CurvePoint(xs[i], ys[i].clamp(0.0, 1.0)),
  ];
}

/// Every curve for one photo, bundled together for [RenderParams] and
/// persistence — the master Tone Curve plus the three Color Curve
/// channels.
class PhotoCurves {
  const PhotoCurves({
    this.tone = identityToneCurve,
    this.red = identityToneCurve,
    this.green = identityToneCurve,
    this.blue = identityToneCurve,
  });

  final List<CurvePoint> tone;
  final List<CurvePoint> red;
  final List<CurvePoint> green;
  final List<CurvePoint> blue;

  bool get isIdentity =>
      isIdentityToneCurve(tone) &&
      isIdentityToneCurve(red) &&
      isIdentityToneCurve(green) &&
      isIdentityToneCurve(blue);

  PhotoCurves copyWith({
    List<CurvePoint>? tone,
    List<CurvePoint>? red,
    List<CurvePoint>? green,
    List<CurvePoint>? blue,
  }) => PhotoCurves(
    tone: tone ?? this.tone,
    red: red ?? this.red,
    green: green ?? this.green,
    blue: blue ?? this.blue,
  );
}

const identityPhotoCurves = PhotoCurves();

/// Linearly interpolates each point in [target] toward the matching point
/// in [base] by [amount] (0..1, 0 = stays at [base], 1 = lands exactly on
/// [target]) — used for a preset's Amount slider (Meridian-style,
/// 0-150%). Falls back to [target] unchanged when the two curves don't
/// have the same number of control points (a mismatched point count has
/// no meaningful "halfway" shape, so partial application isn't
/// well-defined — this only matters for curves imported from elsewhere,
/// since presets created in-app always start from the same identity
/// curve's point count).
List<CurvePoint> lerpCurve(
  List<CurvePoint> base,
  List<CurvePoint> target,
  double amount,
) {
  if (base.length != target.length) {
    return target;
  }
  return [
    for (var i = 0; i < target.length; i++)
      CurvePoint(
        base[i].x + (target[i].x - base[i].x) * amount,
        base[i].y + (target[i].y - base[i].y) * amount,
      ),
  ];
}

/// [lerpCurve], applied to every curve in a [PhotoCurves].
PhotoCurves lerpPhotoCurves(
  PhotoCurves base,
  PhotoCurves target,
  double amount,
) => PhotoCurves(
  tone: lerpCurve(base.tone, target.tone, amount),
  red: lerpCurve(base.red, target.red, amount),
  green: lerpCurve(base.green, target.green, amount),
  blue: lerpCurve(base.blue, target.blue, amount),
);
