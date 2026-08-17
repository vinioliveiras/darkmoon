import 'dart:math' as math;
import 'dart:typed_data';

import 'tone_curve.dart';

/// A linear gradient mask: full effect on the [startX]/[startY] side,
/// fading linearly to zero by [endX]/[endY], staying zero beyond it.
/// Points are normalized to the image's own 0..1 coordinate space (not
/// pixel size), so the mask stays correct across preview/full-quality/
/// export resolutions.
class LinearGradientGeometry {
  const LinearGradientGeometry({
    this.startX = 0.5,
    this.startY = 0.25,
    this.endX = 0.5,
    this.endY = 0.75,
  });

  final double startX;
  final double startY;
  final double endX;
  final double endY;

  LinearGradientGeometry copyWith({
    double? startX,
    double? startY,
    double? endX,
    double? endY,
  }) => LinearGradientGeometry(
    startX: startX ?? this.startX,
    startY: startY ?? this.startY,
    endX: endX ?? this.endX,
    endY: endY ?? this.endY,
  );
}

/// A radial gradient mask: a circle centered at ([centerX], [centerY])
/// with normalized [radius] (a fraction of the image's width, so it
/// renders as a true circle regardless of the photo's aspect ratio) —
/// full effect inside, fading out over the inner [feather] fraction of
/// the radius at the edge.
class RadialGradientGeometry {
  const RadialGradientGeometry({
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.radius = 0.25,
    this.feather = 0.5,
  });

  final double centerX;
  final double centerY;
  final double radius;
  final double feather;

  RadialGradientGeometry copyWith({
    double? centerX,
    double? centerY,
    double? radius,
    double? feather,
  }) => RadialGradientGeometry(
    centerX: centerX ?? this.centerX,
    centerY: centerY ?? this.centerY,
    radius: radius ?? this.radius,
    feather: feather ?? this.feather,
  );
}

/// A color-similarity mask: covers pixels close to a sampled reference
/// color ([r]/[g]/[b], 0..255), within [tolerance] (0..100, how far a
/// pixel's color can be from the reference and still count), fading out
/// over the next [feather] (0..100) of color distance beyond that.
class ColorRangeGeometry {
  const ColorRangeGeometry({
    this.r = 128,
    this.g = 128,
    this.b = 128,
    this.tolerance = 30,
    this.feather = 25,
  });

  final double r;
  final double g;
  final double b;
  final double tolerance;
  final double feather;

  ColorRangeGeometry copyWith({
    double? r,
    double? g,
    double? b,
    double? tolerance,
    double? feather,
  }) => ColorRangeGeometry(
    r: r ?? this.r,
    g: g ?? this.g,
    b: b ?? this.b,
    tolerance: tolerance ?? this.tolerance,
    feather: feather ?? this.feather,
  );
}

/// One point along a brush stroke, normalized to the image's 0..1
/// coordinate space (same convention as the gradient geometries).
class BrushPoint {
  const BrushPoint(this.x, this.y);

  final double x;
  final double y;
}

/// One continuous drag of the brush — a polyline of dabs sharing the same
/// size/hardness/erase setting (matching how brush tools typically fix
/// those per-stroke, adjustable between strokes via the size/hardness
/// controls). [radius] is normalized to the image's width, like the
/// radial gradient's, so the brush stays the same relative size across
/// preview/full-quality/export resolutions.
class BrushStroke {
  const BrushStroke({
    required this.points,
    required this.radius,
    required this.hardness,
    required this.erase,
  });

  final List<BrushPoint> points;
  final double radius;
  final double hardness;
  final bool erase;
}

/// A brush mask's full paint history — strokes are kept as vector data
/// (not a fixed-resolution bitmap) and rasterized at render time, so
/// undo is just dropping the last stroke and the mask stays sharp at any
/// resolution.
class BrushGeometry {
  const BrushGeometry({this.strokes = const []});

  final List<BrushStroke> strokes;

  BrushGeometry copyWith({List<BrushStroke>? strokes}) =>
      BrushGeometry(strokes: strokes ?? this.strokes);
}

enum MaskType { linearGradient, radialGradient, brush, colorRange }

/// One mask "layer": how its region is defined ([type] + geometry), its
/// own independent slider values (same flat `{sliderName: value}` shape
/// as the global adjustments — built into a [RenderParams] the same way),
/// whether it's currently applied, and whether its region is inverted.
class MaskLayer {
  const MaskLayer({
    required this.id,
    required this.name,
    required this.type,
    this.linear = const LinearGradientGeometry(),
    this.radial = const RadialGradientGeometry(),
    this.brush = const BrushGeometry(),
    this.colorRange = const ColorRangeGeometry(),
    this.enabled = true,
    this.inverted = false,
    this.opacity = 100,
    this.values = const {},
    this.curves = identityPhotoCurves,
  });

  final String id;
  final String name;
  final MaskType type;
  final LinearGradientGeometry linear;
  final RadialGradientGeometry radial;
  final BrushGeometry brush;
  final ColorRangeGeometry colorRange;
  final bool enabled;
  final bool inverted;

  /// How strongly this mask's effect applies, 0..100 — scales the mask's
  /// own per-pixel alpha uniformly before compositing (see
  /// [computeMaskAlpha]), the same "Opacity" a Lightroom/Photoshop mask
  /// layer has. 100 (the default) applies at full computed strength,
  /// matching every mask's behavior before this field existed.
  final double opacity;
  final Map<String, double> values;

  /// This mask's own Tone Curve + Color Curve, independent of the global
  /// [PhotoCurves] — mirrors how [values] holds the mask's own slider
  /// values separately from the global `_paramValues`.
  final PhotoCurves curves;

  MaskLayer copyWith({
    LinearGradientGeometry? linear,
    RadialGradientGeometry? radial,
    BrushGeometry? brush,
    ColorRangeGeometry? colorRange,
    bool? enabled,
    bool? inverted,
    double? opacity,
    Map<String, double>? values,
    PhotoCurves? curves,
  }) => MaskLayer(
    id: id,
    name: name,
    type: type,
    linear: linear ?? this.linear,
    radial: radial ?? this.radial,
    brush: brush ?? this.brush,
    colorRange: colorRange ?? this.colorRange,
    enabled: enabled ?? this.enabled,
    inverted: inverted ?? this.inverted,
    opacity: opacity ?? this.opacity,
    values: values ?? this.values,
    curves: curves ?? this.curves,
  );
}

/// Computes [mask]'s per-pixel alpha (0..1) at [width]x[height] —
/// isolate-transferable pure function, same convention as render.dart.
/// [sourceForColorRange] is the packed RGB buffer a Color Range mask
/// samples color distance from (the working buffer as it stands *before*
/// this mask's own layer, matching what the eyedropper picked) — unused
/// by every other mask type.
Float32List computeMaskAlpha(
  MaskLayer mask,
  int width,
  int height, {
  Float32List? sourceForColorRange,
}) {
  final alpha = Float32List(width * height);
  switch (mask.type) {
    case MaskType.linearGradient:
      _computeLinearAlpha(alpha, width, height, mask.linear);
    case MaskType.radialGradient:
      _computeRadialAlpha(alpha, width, height, mask.radial);
    case MaskType.brush:
      _computeBrushAlpha(alpha, width, height, mask.brush);
    case MaskType.colorRange:
      _computeColorRangeAlpha(
        alpha,
        width,
        height,
        sourceForColorRange ?? Float32List(width * height * 3),
        mask.colorRange,
      );
  }
  if (mask.inverted) {
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] = 1.0 - alpha[i];
    }
  }
  final opacityFactor = (mask.opacity / 100.0).clamp(0.0, 1.0);
  if (opacityFactor != 1.0) {
    for (var i = 0; i < alpha.length; i++) {
      alpha[i] *= opacityFactor;
    }
  }
  return alpha;
}

void _computeLinearAlpha(
  Float32List alpha,
  int width,
  int height,
  LinearGradientGeometry g,
) {
  final dx = g.endX - g.startX;
  final dy = g.endY - g.startY;
  final lenSq = dx * dx + dy * dy;
  var p = 0;
  for (var y = 0; y < height; y++) {
    final ny = (y + 0.5) / height;
    for (var x = 0; x < width; x++, p++) {
      final nx = (x + 0.5) / width;
      final t = lenSq <= 0
          ? 0.0
          : ((nx - g.startX) * dx + (ny - g.startY) * dy) / lenSq;
      alpha[p] = (1.0 - t).clamp(0.0, 1.0);
    }
  }
}

void _computeRadialAlpha(
  Float32List alpha,
  int width,
  int height,
  RadialGradientGeometry g,
) {
  final radius = g.radius <= 0 ? 0.0001 : g.radius;
  final innerRadius = radius * (1.0 - g.feather.clamp(0.0, 1.0));
  final cx = g.centerX * width;
  final cy = g.centerY * height;
  // Scales y-distance into the same unit as x-distance (fractions of
  // image width) so the mask renders as a true circle regardless of the
  // photo's aspect ratio, instead of a squashed ellipse.
  final scaleY = width / height;
  var p = 0;
  for (var y = 0; y < height; y++) {
    final ddy = (y - cy) * scaleY;
    for (var x = 0; x < width; x++, p++) {
      final ddx = x - cx;
      final dist = math.sqrt(ddx * ddx + ddy * ddy) / width;
      if (dist <= innerRadius) {
        alpha[p] = 1.0;
      } else if (dist >= radius) {
        alpha[p] = 0.0;
      } else {
        final span = radius - innerRadius;
        alpha[p] = span <= 0 ? 0.0 : 1.0 - (dist - innerRadius) / span;
      }
    }
  }
}

void _computeBrushAlpha(
  Float32List alpha,
  int width,
  int height,
  BrushGeometry g,
) {
  for (final stroke in g.strokes) {
    _paintStroke(alpha, width, height, stroke);
  }
}

/// Dabs a circle (feathered by [BrushStroke.hardness]) at every point of
/// [stroke], only touching the small bounding box around each dab rather
/// than scanning the whole image — cost scales with painted area, not
/// image size.
void _paintStroke(
  Float32List alpha,
  int width,
  int height,
  BrushStroke stroke,
) {
  final radiusPx = stroke.radius * width;
  if (radiusPx <= 0) {
    return;
  }
  final innerPx = radiusPx * stroke.hardness.clamp(0.0, 1.0);
  final span = radiusPx - innerPx;
  final radiusSq = radiusPx * radiusPx;
  for (final point in stroke.points) {
    final cx = point.x * width;
    final cy = point.y * height;
    final minX = math.max(0, (cx - radiusPx).floor());
    final maxX = math.min(width - 1, (cx + radiusPx).ceil());
    final minY = math.max(0, (cy - radiusPx).floor());
    final maxY = math.min(height - 1, (cy + radiusPx).ceil());
    for (var y = minY; y <= maxY; y++) {
      final dy = y - cy;
      final rowOffset = y * width;
      for (var x = minX; x <= maxX; x++) {
        final dx = x - cx;
        final distSq = dx * dx + dy * dy;
        if (distSq > radiusSq) {
          continue;
        }
        final dist = math.sqrt(distSq);
        final coverage = dist <= innerPx
            ? 1.0
            : (span <= 0 ? 0.0 : 1.0 - (dist - innerPx) / span);
        final idx = rowOffset + x;
        if (stroke.erase) {
          alpha[idx] = (alpha[idx] * (1.0 - coverage)).clamp(0.0, 1.0);
        } else if (coverage > alpha[idx]) {
          alpha[idx] = coverage;
        }
      }
    }
  }
}

/// How far (in RGB Euclidean distance, 0..255 per channel) a pixel can be
/// from the reference color at full [ColorRangeGeometry.tolerance]/
/// [ColorRangeGeometry.feather], scaled so 100 on those 0..100 sliders
/// reaches a reasonable chunk of the color space without requiring the
/// full ~441 diagonal.
const _colorRangeMaxCoreDistance = 300.0;
const _colorRangeMaxFeatherDistance = 150.0;

void _computeColorRangeAlpha(
  Float32List alpha,
  int width,
  int height,
  Float32List rgb,
  ColorRangeGeometry g,
) {
  final core =
      g.tolerance.clamp(0.0, 100.0) / 100.0 * _colorRangeMaxCoreDistance;
  final featherSpan =
      g.feather.clamp(0.0, 100.0) / 100.0 * _colorRangeMaxFeatherDistance;
  var p = 0;
  for (var i = 0; i < alpha.length; i++, p += 3) {
    final dr = rgb[p] - g.r;
    final dg = rgb[p + 1] - g.g;
    final db = rgb[p + 2] - g.b;
    final dist = math.sqrt(dr * dr + dg * dg + db * db);
    if (dist <= core) {
      alpha[i] = 1.0;
    } else if (featherSpan <= 0 || dist >= core + featherSpan) {
      alpha[i] = 0.0;
    } else {
      alpha[i] = 1.0 - (dist - core) / featherSpan;
    }
  }
}
