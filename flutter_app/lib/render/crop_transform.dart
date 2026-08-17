import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';

/// Lightroom's Crop Overlay + Transform panels, bundled together since
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
  });

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
  /// -100..100 — Lightroom's Aspect slider.
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

/// Samples packed RGB [src] at fractional `(u, v)` via bilinear
/// interpolation, clamping to the image bounds at the edges rather than
/// producing black — a strong keystone correction can otherwise expose
/// gaps outside the original frame; clamping stretches the edge pixel
/// into that gap instead, which reads better before the user crops it
/// away (Lightroom's own "Fill Edges" content-aware option is well out of
/// scope here).
void _sampleBilinear(
  Uint8List src,
  int width,
  int height,
  double u,
  double v,
  Uint8List out,
  int outIndex,
) {
  final cu = u.clamp(0.0, width - 1.0);
  final cv = v.clamp(0.0, height - 1.0);
  final x0 = cu.floor();
  final y0 = cv.floor();
  final x1 = math.min(x0 + 1, width - 1);
  final y1 = math.min(y0 + 1, height - 1);
  final fx = cu - x0;
  final fy = cv - y0;
  final i00 = (y0 * width + x0) * 3;
  final i10 = (y0 * width + x1) * 3;
  final i01 = (y1 * width + x0) * 3;
  final i11 = (y1 * width + x1) * 3;
  for (var c = 0; c < 3; c++) {
    final top = src[i00 + c] * (1 - fx) + src[i10 + c] * fx;
    final bottom = src[i01 + c] * (1 - fx) + src[i11 + c] * fx;
    out[outIndex + c] = (top * (1 - fy) + bottom * fy).round().clamp(0, 255);
  }
}

/// Applies [params]'s straighten/keystone/scale/crop as a single combined
/// geometric resample of packed RGB [sourceRgb] — the only stage in the
/// render pipeline that changes the buffer's width/height rather than
/// recoloring pixels in place, so it runs once before the color/tone
/// pipeline (`render.dart`) rather than as one of its steps: every
/// downstream stage, including mask alpha (`mask.dart`), then works in
/// this already-cropped/corrected frame, matching how Lightroom's local
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
  final cx = w / 2;
  final cy = h / 2;
  final angleRad = params.straightenAngle * math.pi / 180.0;

  // The straightened rectangle's corners — where the original frame's
  // corners land after just the continuous-angle rotation, before
  // keystone. Order: top-left, top-right, bottom-right, bottom-left.
  final srcCorners = [
    rotatePoint(0, 0, cx, cy, angleRad),
    rotatePoint(w, 0, cx, cy, angleRad),
    rotatePoint(w, h, cx, cy, angleRad),
    rotatePoint(0, h, cx, cy, angleRad),
  ];

  // Keystone: pulls the narrower-appearing edge's corners toward the
  // frame center. `vertical` corrects the top/bottom edges (as if
  // shot from below/above), `horizontal` the left/right edges (as if
  // shot from the side) — `aspect` differentially scales how strongly
  // each applies, matching Lightroom's own three-slider relationship.
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
      _sampleBilinear(
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
