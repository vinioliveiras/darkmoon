import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';

/// Meridian's Crop Overlay + Transform panels, bundled together since
/// Transform's perspective correction and Crop's rectangle both warp/
/// select from the same working canvas and are naturally applied as one
/// combined geometric resample before any color/tone adjustment runs.
class CropTransformParams {
  const CropTransformParams({
    this.straightenAngle = 0,
    this.vertical = 0,
    this.horizontal = 0,
    this.aspect = 0,
    this.scale = 100,
    this.rotateQuarterTurns = 0,
    this.cropLeft = 0,
    this.cropTop = 0,
    this.cropRight = 1,
    this.cropBottom = 1,
    this.constrain = false,
  });

  /// Constrain Crop (2026-09-12), Meridian's checkbox of the same name:
  /// while on, the crop rectangle is kept inside the area the source
  /// actually covers after straightening and keystoning, so the empty
  /// corners a transform leaves never reach the export — see
  /// [constrainCrop]. Not part of [isIdentity]: the switch alone changes
  /// nothing until a transform gives it corners to cut.
  final bool constrain;

  /// Straighten angle, degrees (-45..45). Rotates the whole frame about
  /// its center before the keystone correction below.
  final double straightenAngle;

  /// Vertical perspective correction, -100..100 — keystones the top/
  /// bottom edges toward parallel (correcting converging verticals from
  /// an upward/downward camera angle).
  final double vertical;

  /// Horizontal perspective correction, -100..100 — keystones the left/
  /// right edges toward parallel.
  final double horizontal;

  /// Differential strength between the vertical/horizontal correction,
  /// -100..100 — Meridian's Aspect slider.
  final double aspect;

  /// Post-correction zoom, 100..150% — crops in to hide the empty
  /// corners a strong keystone correction leaves outside the frame.
  final double scale;

  /// 90°-increment rotation (0..3, i.e. 0/90/180/270°) — the Crop tool's
  /// quick-rotate button, kept separate from [straightenAngle]'s
  /// fine-grained continuous angle.
  final int rotateQuarterTurns;

  /// Crop rectangle, normalized 0..1 within the straightened/keystoned/
  /// scaled canvas (i.e. after every other field above is applied, before
  /// this one) — (0,0,1,1) is the full frame, no crop.
  final double cropLeft;
  final double cropTop;
  final double cropRight;
  final double cropBottom;

  bool get isIdentity =>
      straightenAngle == 0 &&
      vertical == 0 &&
      horizontal == 0 &&
      aspect == 0 &&
      scale == 100 &&
      rotateQuarterTurns == 0 &&
      cropLeft == 0 &&
      cropTop == 0 &&
      cropRight == 1 &&
      cropBottom == 1;

  CropTransformParams copyWith({
    double? straightenAngle,
    double? vertical,
    double? horizontal,
    double? aspect,
    double? scale,
    int? rotateQuarterTurns,
    double? cropLeft,
    double? cropTop,
    double? cropRight,
    double? cropBottom,
    bool? constrain,
  }) => CropTransformParams(
    straightenAngle: straightenAngle ?? this.straightenAngle,
    vertical: vertical ?? this.vertical,
    horizontal: horizontal ?? this.horizontal,
    aspect: aspect ?? this.aspect,
    scale: scale ?? this.scale,
    rotateQuarterTurns: rotateQuarterTurns ?? this.rotateQuarterTurns,
    cropLeft: cropLeft ?? this.cropLeft,
    cropTop: cropTop ?? this.cropTop,
    cropRight: cropRight ?? this.cropRight,
    cropBottom: cropBottom ?? this.cropBottom,
    constrain: constrain ?? this.constrain,
  );

  /// Builds params from the editor's flat `{sliderName: value}` map, same
  /// convention as every other adjustment.
  factory CropTransformParams.fromValues(Map<String, double> values) {
    const d = CropTransformParams();
    return CropTransformParams(
      straightenAngle: values['TransformStraighten'] ?? d.straightenAngle,
      vertical: values['TransformVertical'] ?? d.vertical,
      horizontal: values['TransformHorizontal'] ?? d.horizontal,
      aspect: values['TransformAspect'] ?? d.aspect,
      scale: values['TransformScale'] ?? d.scale,
      rotateQuarterTurns:
          values['CropRotateQuarterTurns']?.round() ?? d.rotateQuarterTurns,
      cropLeft: values['CropLeft'] ?? d.cropLeft,
      cropTop: values['CropTop'] ?? d.cropTop,
      cropRight: values['CropRight'] ?? d.cropRight,
      cropBottom: values['CropBottom'] ?? d.cropBottom,
      constrain: (values['CropConstrain'] ?? 0) != 0,
    );
  }

  Map<String, double> toValues() => {
    'TransformStraighten': straightenAngle,
    'TransformVertical': vertical,
    'TransformHorizontal': horizontal,
    'TransformAspect': aspect,
    'TransformScale': scale,
    'CropRotateQuarterTurns': rotateQuarterTurns.toDouble(),
    'CropLeft': cropLeft,
    'CropTop': cropTop,
    'CropRight': cropRight,
    'CropBottom': cropBottom,
    'CropConstrain': constrain ? 1.0 : 0.0,
  };
}

class GeometryResult {
  const GeometryResult({
    required this.width,
    required this.height,
    required this.rgbBytes,
  });

  final int width;
  final int height;
  final Uint8List rgbBytes;
}

/// Rotates packed RGB [src] ([width]x[height]) by a multiple of 90°,
/// swapping width/height for odd turn counts. Exact (no resampling) since
/// quarter turns are pure pixel permutations.
GeometryResult _rotateQuarterTurns(
  Uint8List src,
  int width,
  int height,
  int turns,
) {
  final normalizedTurns = turns % 4;
  if (normalizedTurns == 0) {
    return GeometryResult(width: width, height: height, rgbBytes: src);
  }
  final newWidth = normalizedTurns.isOdd ? height : width;
  final newHeight = normalizedTurns.isOdd ? width : height;
  final out = Uint8List(src.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final srcI = (y * width + x) * 3;
      int dx, dy;
      switch (normalizedTurns) {
        case 1: // 90° clockwise
          dx = height - 1 - y;
          dy = x;
        case 2: // 180°
          dx = width - 1 - x;
          dy = height - 1 - y;
        default: // 3, 270° clockwise
          dx = y;
          dy = width - 1 - x;
      }
      final dstI = (dy * newWidth + dx) * 3;
      out[dstI] = src[srcI];
      out[dstI + 1] = src[srcI + 1];
      out[dstI + 2] = src[srcI + 2];
    }
  }
  return GeometryResult(width: newWidth, height: newHeight, rgbBytes: out);
}

/// Applies [params]'s straighten/keystone/scale/crop as a single combined
/// geometric resample of packed RGB [sourceRgb] — the only stage in the
/// render pipeline that changes the buffer's width/height rather than
/// recoloring pixels in place, so it runs once before the color/tone
/// pipeline (`render.dart`) rather than as one of its steps: every
/// downstream stage, including mask alpha (`mask.dart`), then works in
/// this already-cropped/corrected frame, matching how Meridian's local
/// adjustments are defined against the post-crop image.
///
/// Returns [sourceRgb] unchanged (wrapped, no copy) when [params] is
/// identity, so photos that never touch Crop/Transform pay zero extra
/// cost.
GeometryResult applyCropTransform(
  Uint8List sourceRgb,
  int width,
  int height,
  CropTransformParams params,
) {
  if (params.isIdentity) {
    return GeometryResult(width: width, height: height, rgbBytes: sourceRgb);
  }

  final rotated = _rotateQuarterTurns(
    sourceRgb,
    width,
    height,
    params.rotateQuarterTurns,
  );
  final w = rotated.width.toDouble();
  final h = rotated.height.toDouble();
  final frame = _frameFor(params, w, h);
  final cx = frame.cx;
  final cy = frame.cy;
  final angleRad = frame.angleRad;
  final inverse = frame.inverse;

  final cropLeftPx = (params.cropLeft.clamp(0.0, 1.0) * w);
  final cropTopPx = (params.cropTop.clamp(0.0, 1.0) * h);
  final cropRightPx = (params.cropRight.clamp(0.0, 1.0) * w);
  final cropBottomPx = (params.cropBottom.clamp(0.0, 1.0) * h);
  final outWidth = math.max(1, (cropRightPx - cropLeftPx).round());
  final outHeight = math.max(1, (cropBottomPx - cropTopPx).round());

  final out = Uint8List(outWidth * outHeight * 3);
  for (var oy = 0; oy < outHeight; oy++) {
    final canvasY = cropTopPx + oy + 0.5;
    for (var ox = 0; ox < outWidth; ox++) {
      final canvasX = cropLeftPx + ox + 0.5;
      // canvas (post-keystone) -> straightened-source-space -> original
      // (pre-rotation) source pixel coordinates.
      final straightened = inverse.transformPoint(canvasX, canvasY);
      final original = rotatePoint(
        straightened[0],
        straightened[1],
        cx,
        cy,
        -angleRad,
      );
      sampleBilinear(
        rotated.rgbBytes,
        rotated.width,
        rotated.height,
        original[0],
        original[1],
        out,
        (oy * outWidth + ox) * 3,
      );
    }
  }

  return GeometryResult(width: outWidth, height: outHeight, rgbBytes: out);
}

/// The transform's per-frame constants: the straighten angle and the
/// keystone+scale homography between straightened-source space and the
/// canvas, for a [w] x [h] canvas (after quarter turns). Shared by
/// [applyCropTransform] and [validCanvasQuad] so the two can never
/// disagree about where the content lands.
class _TransformFrame {
  const _TransformFrame({
    required this.cx,
    required this.cy,
    required this.angleRad,
    required this.forward,
    required this.inverse,
  });
  final double cx;
  final double cy;
  final double angleRad;
  final Matrix3 forward;
  final Matrix3 inverse;
}

_TransformFrame _frameFor(CropTransformParams params, double w, double h) {
  final cx = w / 2;
  final cy = h / 2;
  final angleRad = params.straightenAngle * math.pi / 180.0;

  // The plain canvas rect, AS IT APPEARS in "straightened-source-space" —
  // by definition that space is already upright (that's what "straightened"
  // means), so these corners are just (0,0)-(w,h), not rotated. The actual
  // rotation is applied once, explicitly, in the sampling loop below
  // (`rotatePoint(..., -angleRad)`) — rotating these corners here too was
  // a bug: `forward` would then be an actual rotation, `inverse` its
  // opposite, and composing that with the explicit -angleRad rotation
  // below canceled out exactly whenever keystone was off (the overwhelming
  // common case), making the Straighten slider a visible no-op. Order:
  // top-left, top-right, bottom-right, bottom-left.
  final srcCorners = [
    [0.0, 0.0],
    [w, 0.0],
    [w, h],
    [0.0, h],
  ];

  // Keystone: pulls the narrower-appearing edge's corners toward the
  // frame center. `vertical` corrects the top/bottom edges (as if
  // shot from below/above), `horizontal` the left/right edges (as if
  // shot from the side) — `aspect` differentially scales how strongly
  // each applies, matching Meridian's own three-slider relationship.
  final vFactor = (params.vertical / 100.0) * 0.5 * (1 + params.aspect / 200);
  final hFactor = (params.horizontal / 100.0) * 0.5 * (1 - params.aspect / 200);
  final dstCorners = [
    [0.0 + vFactor * w, 0.0 + hFactor * h],
    [w - vFactor * w, 0.0 - hFactor * h],
    [w, h],
    [0.0, h],
  ];

  // Scale (100..150%) zooms in about the canvas center by shrinking the
  // destination quad toward it — the source content that used to span
  // the whole canvas then only spans a smaller centered region, which
  // (once inverted below for sampling) reads as a zoom-in that crops out
  // the empty corners a strong keystone leaves behind.
  final scaleFactor = 1.0 / (params.scale / 100.0).clamp(1.0, 1.5);
  for (final corner in dstCorners) {
    corner[0] = cx + (corner[0] - cx) * scaleFactor;
    corner[1] = cy + (corner[1] - cy) * scaleFactor;
  }

  final forward = solveHomography(srcCorners, dstCorners);
  final inverse = forward.invert();
  return _TransformFrame(
    cx: cx,
    cy: cy,
    angleRad: angleRad,
    forward: forward,
    inverse: inverse,
  );
}

/// A rectangle in the canvas's normalised 0..1 space, the unit
/// [CropTransformParams.cropLeft] and friends use.
typedef NormRect = ({double left, double top, double right, double bottom});

/// The quadrilateral of the canvas the source still covers after
/// [params]'s straighten, keystone and scale — normalised to the canvas
/// (the frame after quarter turns, [width] x [height] being the source's
/// own size). Everything outside it is the empty corner a transform
/// leaves behind. Top-left, top-right, bottom-right, bottom-left.
List<List<double>> validCanvasQuad(
  CropTransformParams params,
  int width,
  int height,
) {
  final turned = params.rotateQuarterTurns.isOdd;
  final w = (turned ? height : width).toDouble();
  final h = (turned ? width : height).toDouble();
  final frame = _frameFor(params, w, h);
  final corners = [
    [0.0, 0.0],
    [w, 0.0],
    [w, h],
    [0.0, h],
  ];
  final out = <List<double>>[];
  for (final c in corners) {
    // Source -> straightened space (the sampling loop rotates the other
    // way, by -angle) -> canvas.
    final st = rotatePoint(c[0], c[1], frame.cx, frame.cy, frame.angleRad);
    final pt = frame.forward.transformPoint(st[0], st[1]);
    out.add([pt[0] / w, pt[1] / h]);
  }
  return out;
}

/// Whether the normalised [rect] lies entirely inside the convex [quad].
bool rectInsideQuad(NormRect rect, List<List<double>> quad) {
  const eps = 1e-6;
  for (final p in [
    [rect.left, rect.top],
    [rect.right, rect.top],
    [rect.right, rect.bottom],
    [rect.left, rect.bottom],
  ]) {
    if (!_pointInConvexQuad(p[0], p[1], quad, eps)) return false;
  }
  return true;
}

bool _pointInConvexQuad(
  double x,
  double y,
  List<List<double>> quad,
  double eps,
) {
  double? sign;
  for (var i = 0; i < 4; i++) {
    final a = quad[i], b = quad[(i + 1) % 4];
    final cross = (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0]);
    if (cross.abs() <= eps) continue;
    final sgn = cross.sign;
    if (sign == null) {
      sign = sgn;
    } else if (sgn != sign) {
      return false;
    }
  }
  return true;
}

/// The horizontal extent of the convex [quad] at height [y], or null when
/// the line misses it.
(double, double)? _spanAt(List<List<double>> quad, double y) {
  double? lo, hi;
  for (var i = 0; i < 4; i++) {
    final a = quad[i], b = quad[(i + 1) % 4];
    final y0 = a[1], y1 = b[1];
    if (y < math.min(y0, y1) || y > math.max(y0, y1)) continue;
    if ((y1 - y0).abs() < 1e-12) {
      // A horizontal edge: both ends count.
      lo = math.min(lo ?? a[0], math.min(a[0], b[0]));
      hi = math.max(hi ?? a[0], math.max(a[0], b[0]));
      continue;
    }
    final x = a[0] + (b[0] - a[0]) * (y - y0) / (y1 - y0);
    lo = math.min(lo ?? x, x);
    hi = math.max(hi ?? x, x);
  }
  return lo == null || hi == null ? null : (lo, hi);
}

/// The largest axis-aligned rectangle inside the convex [quad]
/// ([validCanvasQuad]'s), by area — at [aspect] (canvas width / height in
/// pixels, for a [canvasWidth] x [canvasHeight] canvas) when one is
/// given. A grid search over the top and bottom edges: for a convex
/// shape the rectangle between two heights can use whatever width both
/// heights allow, so each pair is one evaluation.
NormRect largestInscribedRect(
  List<List<double>> quad, {
  double? aspect,
  int canvasWidth = 3,
  int canvasHeight = 2,
  int steps = 160,
}) {
  final ys = quad.map((p) => p[1]).toList()..sort();
  final yMin = math.max(0.0, ys.first), yMax = math.min(1.0, ys.last);
  NormRect best = (left: 0.0, top: 0.0, right: 0.0, bottom: 0.0);
  var bestArea = -1.0;
  // aspect is in pixels; the normalised rect's width/height ratio is
  // aspect * canvasHeight / canvasWidth.
  final normAspect = aspect == null
      ? null
      : aspect * canvasHeight / canvasWidth;
  for (var i = 0; i <= steps; i++) {
    final y1 = yMin + (yMax - yMin) * i / steps;
    final s1 = _spanAt(quad, y1);
    if (s1 == null) continue;
    for (var j = i + 1; j <= steps; j++) {
      final y2 = yMin + (yMax - yMin) * j / steps;
      final s2 = _spanAt(quad, y2);
      if (s2 == null) continue;
      var left = math.max(0.0, math.max(s1.$1, s2.$1));
      var right = math.min(1.0, math.min(s1.$2, s2.$2));
      if (right <= left) continue;
      var top = y1, bottom = y2;
      if (normAspect != null) {
        final availW = right - left, availH = bottom - top;
        if (availW / availH > normAspect) {
          final wanted = availH * normAspect;
          final mid = (left + right) / 2;
          left = mid - wanted / 2;
          right = mid + wanted / 2;
        } else {
          final wanted = availW / normAspect;
          final mid = (top + bottom) / 2;
          top = mid - wanted / 2;
          bottom = mid + wanted / 2;
        }
      }
      final area = (right - left) * (bottom - top);
      final candidate = (left: left, top: top, right: right, bottom: bottom);
      if (area > bestArea && rectInsideQuad(candidate, quad)) {
        bestArea = area;
        best = candidate;
      }
    }
  }
  if (bestArea < 0) {
    return (left: 0.0, top: 0.0, right: 1.0, bottom: 1.0);
  }
  return best;
}

/// Constrain Crop for a [width] x [height] source: with
/// [CropTransformParams.constrain] on, the crop becomes the largest
/// rectangle the content still covers (at [aspect], pixels, when set)
/// when [snap] is true — a transform just changed — and otherwise only
/// when the current crop pokes outside the content. Off, [params] come
/// back untouched.
CropTransformParams constrainCrop(
  CropTransformParams params,
  int width,
  int height, {
  double? aspect,
  required bool snap,
}) {
  if (!params.constrain) {
    return params;
  }
  final quad = validCanvasQuad(params, width, height);
  final NormRect current = (
    left: params.cropLeft,
    top: params.cropTop,
    right: params.cropRight,
    bottom: params.cropBottom,
  );
  if (!snap && rectInsideQuad(current, quad)) {
    return params;
  }
  final turned = params.rotateQuarterTurns.isOdd;
  final rect = largestInscribedRect(
    quad,
    aspect: aspect,
    canvasWidth: turned ? height : width,
    canvasHeight: turned ? width : height,
  );
  return params.copyWith(
    cropLeft: rect.left,
    cropTop: rect.top,
    cropRight: rect.right,
    cropBottom: rect.bottom,
  );
}
