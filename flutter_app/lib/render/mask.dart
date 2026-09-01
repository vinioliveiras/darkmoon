import 'dart:math' as math;
import 'dart:typed_data';

import 'luminance.dart' show luminanceRgb;
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

/// A radial gradient mask: an ellipse centered at ([centerX], [centerY])
/// with semi-axes [radius] (along the shape's own X axis) and [radiusY]
/// (along its Y axis), both normalized to the image's width — so equal
/// values render as a true circle on screen regardless of the photo's
/// aspect ratio. The whole shape rotates by [angle]. Full effect inside,
/// fading out over the outer [feather] fraction of the shape.
class RadialGradientGeometry {
  const RadialGradientGeometry({
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.radius = 0.25,
    this.radiusY,
    this.angle = 0.0,
    this.feather = 0.5,
  });

  final double centerX;
  final double centerY;

  /// Semi-axis along the ellipse's own X direction, as a fraction of the
  /// image's width.
  final double radius;

  /// Semi-axis along the ellipse's own Y direction, in the same
  /// width-relative unit as [radius]. Null means "same as [radius]" — a
  /// circle — which is also what masks saved before ellipse support
  /// existed decode to. Use [effectiveRadiusY] when computing.
  final double? radiusY;

  /// Rotation of the ellipse around its center, in radians — positive is
  /// clockwise on screen (Flutter's y-down convention). 0 keeps the
  /// [radius] axis horizontal.
  final double angle;

  final double feather;

  /// [radiusY] with the circle fallback applied.
  double get effectiveRadiusY => radiusY ?? radius;

  RadialGradientGeometry copyWith({
    double? centerX,
    double? centerY,
    double? radius,
    double? radiusY,
    double? angle,
    double? feather,
  }) => RadialGradientGeometry(
    centerX: centerX ?? this.centerX,
    centerY: centerY ?? this.centerY,
    radius: radius ?? this.radius,
    radiusY: radiusY ?? this.radiusY,
    angle: angle ?? this.angle,
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

/// A luminance-similarity mask: covers pixels whose brightness is close to
/// a sampled reference luma ([targetLuma], 0..255 — Rec.709-weighted, see
/// `luminance.dart`'s `luminanceRgb`, the same convention this app's
/// luminance-only adjustments already use), within [tolerance] (0..100),
/// fading out over the next [feather] (0..100) of luma distance beyond
/// that. Deliberately mirrors [ColorRangeGeometry] field-for-field (single
/// luma value in place of r/g/b) — same eyedropper-then-tune workflow, one
/// axis instead of three.
class LuminanceGeometry {
  const LuminanceGeometry({
    this.targetLuma = 128,
    this.tolerance = 30,
    this.feather = 25,
  });

  final double targetLuma;
  final double tolerance;
  final double feather;

  LuminanceGeometry copyWith({
    double? targetLuma,
    double? tolerance,
    double? feather,
  }) => LuminanceGeometry(
    targetLuma: targetLuma ?? this.targetLuma,
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
///
/// [flow] (0..100, default 100 — full deposit, matching every stroke's
/// behavior before this field existed) only matters for
/// [MaskType.flow] — see [_computeFlowAlpha]'s doc for what it changes.
/// [MaskType.brush] ignores it entirely (always paints at full coverage
/// in one pass, same as before); both mask types share this one geometry
/// class/stroke list rather than duplicating it, since the only
/// difference between Brush and Flow is how a stroke's coverage
/// composites into the mask, not how the stroke itself is drawn/stored.
class BrushStroke {
  const BrushStroke({
    required this.points,
    required this.radius,
    required this.hardness,
    required this.erase,
    this.flow = 100,
  });

  final List<BrushPoint> points;
  final double radius;
  final double hardness;
  final bool erase;
  final double flow;
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

/// [luminance]: parametric brightness-range selection, same
/// eyedropper-then-tune shape as [colorRange] (see [LuminanceGeometry]).
/// [flow]: a Brush variant with a different per-stroke compositing rule —
/// shares [MaskLayer.brush]'s [BrushGeometry]/stroke storage entirely
/// rather than getting its own field (see [BrushStroke.flow]'s doc for
/// why).
enum MaskType { linearGradient, radialGradient, brush, colorRange, luminance, flow }

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
    this.luminance = const LuminanceGeometry(),
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

  /// Also [MaskType.flow]'s stroke storage — see [MaskType.flow]'s doc.
  final BrushGeometry brush;
  final ColorRangeGeometry colorRange;
  final LuminanceGeometry luminance;
  final bool enabled;
  final bool inverted;

  /// How strongly this mask's effect applies, 0..100 — scales the mask's
  /// own per-pixel alpha uniformly before compositing (see
  /// [computeMaskAlpha]), the same "Opacity" a Meridian/Photoshop mask
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
    LuminanceGeometry? luminance,
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
    luminance: luminance ?? this.luminance,
    enabled: enabled ?? this.enabled,
    inverted: inverted ?? this.inverted,
    opacity: opacity ?? this.opacity,
    values: values ?? this.values,
    curves: curves ?? this.curves,
  );
}

/// Computes [mask]'s per-pixel alpha (0..1) at [width]x[height] —
/// isolate-transferable pure function, same convention as render.dart.
/// [sourceForColorRange] is the packed RGB buffer a Color Range or
/// Luminance mask samples color/brightness distance from (the working
/// buffer as it stands *before* this mask's own layer, matching what the
/// eyedropper picked) — unused by every other mask type. (Kept the
/// Color-Range-specific parameter name rather than renaming to something
/// generic like `sourceRgb` — renaming would touch every call site for
/// a purely cosmetic reason.)
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
    case MaskType.luminance:
      _computeLuminanceAlpha(
        alpha,
        width,
        height,
        sourceForColorRange ?? Float32List(width * height * 3),
        mask.luminance,
      );
    case MaskType.flow:
      _computeFlowAlpha(alpha, width, height, mask.brush);
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
  // Both semi-axes are fractions of the image *width*, so the pixel-space
  // shape is exactly what the overlay draws — a true circle when they're
  // equal — whatever the photo's aspect ratio.
  final rxFrac = g.radius <= 0 ? 0.0001 : g.radius;
  final ryFrac = g.effectiveRadiusY <= 0 ? 0.0001 : g.effectiveRadiusY;
  final invRx = 1.0 / (rxFrac * width);
  final invRy = 1.0 / (ryFrac * width);
  // Feather works on the normalized elliptical distance (1.0 exactly on
  // the boundary), so it scales with the shape instead of being a fixed
  // pixel band.
  final innerFrac = 1.0 - g.feather.clamp(0.0, 1.0);
  final span = 1.0 - innerFrac;
  final cx = g.centerX * width;
  final cy = g.centerY * height;
  final cosA = math.cos(g.angle);
  final sinA = math.sin(g.angle);
  var p = 0;
  for (var y = 0; y < height; y++) {
    final dy = y - cy;
    for (var x = 0; x < width; x++, p++) {
      final dx = x - cx;
      // Rotate the delta into the ellipse's own frame, then normalize
      // each component by its semi-axis: t == 1 on the boundary.
      final u = (dx * cosA + dy * sinA) * invRx;
      final v = (dy * cosA - dx * sinA) * invRy;
      final t = math.sqrt(u * u + v * v);
      if (t <= innerFrac) {
        alpha[p] = 1.0;
      } else if (t >= 1.0) {
        alpha[p] = 0.0;
      } else {
        alpha[p] = span <= 0 ? 0.0 : 1.0 - (t - innerFrac) / span;
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

/// Same proportional core/feather scale [_computeColorRangeAlpha] uses,
/// rescaled from RGB's ~441 max Euclidean diagonal down to luma's 0..255
/// range (300/441 and 150/441 of the diagonal, applied to 255 instead) —
/// keeps the Tolerance/Feather sliders feeling the same between the two
/// mask types despite the different distance metric.
const _luminanceMaxCoreDistance = 173.0;
const _luminanceMaxFeatherDistance = 87.0;

void _computeLuminanceAlpha(
  Float32List alpha,
  int width,
  int height,
  Float32List rgb,
  LuminanceGeometry g,
) {
  final core =
      g.tolerance.clamp(0.0, 100.0) / 100.0 * _luminanceMaxCoreDistance;
  final featherSpan =
      g.feather.clamp(0.0, 100.0) / 100.0 * _luminanceMaxFeatherDistance;
  var p = 0;
  for (var i = 0; i < alpha.length; i++, p += 3) {
    final luma = luminanceRgb(rgb[p], rgb[p + 1], rgb[p + 2]);
    final dist = (luma - g.targetLuma).abs();
    if (dist <= core) {
      alpha[i] = 1.0;
    } else if (featherSpan <= 0 || dist >= core + featherSpan) {
      alpha[i] = 0.0;
    } else {
      alpha[i] = 1.0 - (dist - core) / featherSpan;
    }
  }
}

void _computeFlowAlpha(
  Float32List alpha,
  int width,
  int height,
  BrushGeometry g,
) {
  for (final stroke in g.strokes) {
    _paintFlowStroke(alpha, width, height, stroke);
  }
}

/// [MaskType.flow]'s counterpart to [_paintStroke] — same per-dab
/// distance/feather footprint (`radiusPx`/`innerPx`/`coverage`), but a
/// different final compositing rule: rather than [_paintStroke]'s direct
/// "replace with this dab's coverage if it's stronger" (a single pass
/// over the same pixel can't exceed that dab's own coverage), each dab
/// only *deposits* `coverage * (stroke.flow/100)` of alpha via standard
/// "over" compositing (`next = a + d - a*d`) — so a single continuous
/// stroke only ever reaches `flow%` opacity in one pass, and repeated
/// overlapping strokes are what build up to full coverage. This is the
/// entire difference between Brush and Flow (see [BrushStroke.flow]'s
/// doc) — everything else about how a stroke is drawn/stored is shared.
/// Kept as a separate function rather than a shared one with a branch,
/// since that branch would sit inside this loop's per-pixel hot path for
/// no real reuse benefit (the two compositing formulas share no code).
void _paintFlowStroke(
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
  final flowFraction = (stroke.flow / 100.0).clamp(0.0, 1.0);
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
        final deposit = coverage * flowFraction;
        if (deposit <= 0) {
          continue;
        }
        final idx = rowOffset + x;
        final a = alpha[idx];
        alpha[idx] = stroke.erase
            ? (a * (1.0 - deposit)).clamp(0.0, 1.0)
            : (a + deposit - a * deposit).clamp(0.0, 1.0);
      }
    }
  }
}
