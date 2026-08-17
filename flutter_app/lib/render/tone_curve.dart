import 'dart:typed_data';

/// A single draggable control point on the tone curve, normalized to
/// 0..1 on both axes — (0,0) is pure black in/out, (1,1) is pure white
/// in/out, matching Lightroom's Tone Curve panel.
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
/// already sorted by x) using Catmull-Rom interpolation through the
/// control points, for a smooth curve rather than sharp linear segments.
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
  var seg = points.length - 2;
  for (var i = 0; i < points.length - 1; i++) {
    if (x <= points[i + 1].x) {
      seg = i;
      break;
    }
  }
  final p1 = points[seg];
  final p2 = points[seg + 1];
  final p0 = seg > 0 ? points[seg - 1] : p1;
  final p3 = seg + 2 < points.length ? points[seg + 2] : p2;
  final segWidth = p2.x - p1.x;
  final t = segWidth <= 0 ? 0.0 : (x - p1.x) / segWidth;
  return _catmullRom(p0.y, p1.y, p2.y, p3.y, t);
}

double _catmullRom(double p0, double p1, double p2, double p3, double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  return 0.5 *
      ((2 * p1) +
          (-p0 + p2) * t +
          (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
          (-p0 + 3 * p1 - 3 * p2 + p3) * t3);
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
/// [target]) — used for a preset's Amount slider (Lightroom-style,
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
