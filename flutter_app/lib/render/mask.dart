import 'dart:math' as math;
import 'dart:typed_data';

import 'luminance.dart' show luminanceRgb;
import 'render_params.dart';
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
    this.feather = 100,
  });

  final double startX;
  final double startY;
  final double endX;
  final double endY;

  /// How much of the start-to-end span the fade takes, in percent,
  /// centred on the midpoint (user's request, 2026-09-12): at 100 the
  /// fade runs the whole way from [startX],[startY] to [endX],[endY], the
  /// way it always did; at 20 it is a band a fifth as wide around the
  /// middle, and the rest of the span is full or nothing. The midpoint
  /// is always half strength, so the lines the handles show keep meaning
  /// "full by here" and "gone by here" for the widest fade.
  final double feather;

  LinearGradientGeometry copyWith({
    double? startX,
    double? startY,
    double? endX,
    double? endY,
    double? feather,
  }) => LinearGradientGeometry(
    startX: startX ?? this.startX,
    startY: startY ?? this.startY,
    endX: endX ?? this.endX,
    endY: endY ?? this.endY,
    feather: feather ?? this.feather,
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

/// What a [MaskType.subject] mask points the segmentation model at: the
/// rectangle the user dragged over the thing they want selected, in the
/// image's own 0..1 coordinate space. A degenerate rectangle (start ==
/// end, i.e. a single click) is a *point* prompt rather than a box one —
/// the model takes both, and clicking one object is the faster gesture
/// when it doesn't need bounding.
///
/// Unlike every other geometry here, this doesn't describe the mask's
/// shape — it describes the question asked of the model. The answer
/// (an [AiMaskMap]) is far too big to live in a mask layer and is cached
/// separately; see [computeMaskAlpha]'s [AiMaskMap] parameter.
class SubjectGeometry {
  const SubjectGeometry({
    this.startX = 0.35,
    this.startY = 0.35,
    this.endX = 0.65,
    this.endY = 0.65,
    this.feather = 0,
  });

  final double startX;
  final double startY;
  final double endX;
  final double endY;

  /// How soft the segmentation's edge is, 0..100 (user's request,
  /// 2026-09-12): the model's map is blurred by up to
  /// [aiMaskFeatherMaxFraction] of the frame's width at 100. Shared by
  /// Subject, Sky and Foreground, whose masks all carry this geometry.
  final double feather;

  /// True when the user clicked rather than dragged — see the class doc.
  bool get isPoint =>
      (startX - endX).abs() < 1e-6 && (startY - endY).abs() < 1e-6;

  SubjectGeometry copyWith({
    double? startX,
    double? startY,
    double? endX,
    double? endY,
    double? feather,
  }) => SubjectGeometry(
    startX: startX ?? this.startX,
    startY: startY ?? this.startY,
    endX: endX ?? this.endX,
    endY: endY ?? this.endY,
    feather: feather ?? this.feather,
  );
}

/// A band-pass over the estimated depth map: covers pixels whose depth
/// falls between [near] and [far], fading out over the next [feather] of
/// depth beyond each edge.
///
/// Depth runs 0 (the farthest thing in the frame) to 1 (the nearest) —
/// the model estimates *relative* depth, normalized per photo, so these
/// are never metres and the same 0.5 means different distances in two
/// different photos. [near] is the closer edge of the band, so
/// `near: 1, far: 0.5` selects the front half of the scene.
///
/// Sliders here only re-run this band-pass; the depth map itself is
/// cached and not re-inferred (see [computeMaskAlpha]).
class DepthGeometry {
  const DepthGeometry({this.near = 1.0, this.far = 0.5, this.feather = 25});

  final double near;
  final double far;

  /// 0..100, as a fraction of the full 0..1 depth range.
  final double feather;

  DepthGeometry copyWith({double? near, double? far, double? feather}) =>
      DepthGeometry(
        near: near ?? this.near,
        far: far ?? this.far,
        feather: feather ?? this.feather,
      );
}

/// A model's answer for one AI mask: an 8-bit grayscale map, row-major,
/// [width] x [height], covering the same frame the render runs on (the
/// buffer *after* lens correction and crop — see `render_job.dart`'s
/// `prepareRenderGeometry`), just at a smaller working resolution.
///
/// 8-bit rather than [Float32List] because these cross an isolate boundary
/// and get cached to disk on every render: a 1024-long-side map is 700 KB
/// this way and 2.8 MB the other, for a precision no mask edge can show.
/// Resampled up to the render's real dimensions by [computeMaskAlpha],
/// which is a plain scale — the map already lives in the cropped frame, so
/// there is no geometry to reapply.
class AiMaskMap {
  const AiMaskMap({
    required this.width,
    required this.height,
    required this.data,
  });

  final int width;
  final int height;

  /// [width] * [height] bytes, row-major. For a segmentation mask
  /// (Subject/Sky/Foreground) 255 means "in"; for Depth, 255 is the
  /// nearest point in the frame.
  final Uint8List data;
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

/// [wholeImage]: no geometry at all — every pixel at full weight (see
/// [_computeWholeImageAlpha]). [luminance]: parametric brightness-range
/// selection, same eyedropper-then-tune shape as [colorRange] (see
/// [LuminanceGeometry]). [flow]: a Brush variant with a different
/// per-stroke compositing rule — shares [MaskLayer.brush]'s
/// [BrushGeometry]/stroke storage entirely rather than getting its own
/// field (see [BrushStroke.flow]'s doc for why).
///
/// [subject], [sky], [foreground] and [depth] are the four whose alpha a
/// neural network decides rather than a formula. They are why
/// [computeMaskAlpha] takes an [AiMaskMap]: inference is far too slow and
/// far too asynchronous to happen inside a pure function that reruns on
/// every render, so the map is computed once, cached, and handed in. The
/// three segmentation types differ only in which model and which prompt
/// produced that map — the alpha math is identical, so they share
/// [_computeSegmentAlpha].
///
/// Serialized by *name* (`mask_store.dart`'s `MaskType.values.byName`),
/// so this list's order is free to change without touching saved photos.
enum MaskType {
  linearGradient,
  radialGradient,
  brush,
  colorRange,
  wholeImage,
  luminance,
  flow,
  subject,
  sky,
  foreground,
  depth,
}

/// The types whose alpha comes from a model rather than a formula — the
/// ones needing an [AiMaskMap] resolved before they can render.
const aiMaskTypes = <MaskType>{
  MaskType.subject,
  MaskType.sky,
  MaskType.foreground,
  MaskType.depth,
};

/// One mask "layer": how its region is defined ([type] + geometry), its
/// own independent slider values (same flat `{sliderName: value}` shape
/// as the global adjustments — built into a [RenderParams] the same way),
/// whether it's currently applied, and whether its region is inverted.
/// The render params one mask layer is applied with.
///
/// Shared by the CPU and GPU mask paths because they drifted apart when
/// they were not. The GPU path built its own copy and left [renderScale]
/// out, so every mask layer rendered its neighbourhood stages as if the
/// frame were the reference size no matter how big it actually was.
/// Measured on the CPU renderer at a full-quality preview's scale and at
/// an export's, against the same values at the reference scale: Sharpen
/// went from doing nothing at all to a mean of 6.8 levels, Texture from a
/// third of its strength to full, Clarity from about 58%. Which is
/// exactly how it was reported — a mask's effect being far too weak.
///
/// [baseContrast] is zero because the base "profile" curve belongs to the
/// base image alone; a mask layer renders over the already-profiled
/// buffer, so applying it again would double the contrast under the mask.
RenderParams maskLayerParams(MaskLayer mask, RenderParams globalParams) =>
    RenderParams.fromValues(
      mask.values,
      curves: mask.curves,
      asShotKelvin: globalParams.asShotKelvin,
      asShotTint: globalParams.asShotTint,
      baseContrast: 0,
      // Inherited, never re-derived: a mask layer renders over the same
      // frame as the global layer, so its radii must scale identically.
      renderScale: globalParams.renderScale,
    );

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
    this.subject = const SubjectGeometry(),
    this.depth = const DepthGeometry(),
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

  /// The prompt a [MaskType.subject] mask hands the model — not its shape.
  final SubjectGeometry subject;

  /// The band a [MaskType.depth] mask keeps out of the estimated depth
  /// map. [MaskType.sky] and [MaskType.foreground] have no geometry at
  /// all: nothing about them is the user's to aim.
  final DepthGeometry depth;
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
    SubjectGeometry? subject,
    DepthGeometry? depth,
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
    subject: subject ?? this.subject,
    depth: depth ?? this.depth,
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
///
/// [aiMap] is the model output backing a [MaskType.subject]/[MaskType.sky]/
/// [MaskType.foreground]/[MaskType.depth] mask, resolved by the caller
/// (`ai_mask_resolver.dart`) before the render starts, since running a
/// model here is impossible: this function is synchronous by contract —
/// `render.dart` calls it inside a `compute()` isolate — and inference
/// takes seconds. A null [aiMap] for one of those four types is the normal
/// "not computed yet" state, not an error, and yields an empty mask so the
/// photo simply renders unaffected until the map lands.
Float32List computeMaskAlpha(
  MaskLayer mask,
  int width,
  int height, {
  Float32List? sourceForColorRange,
  AiMaskMap? aiMap,
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
    case MaskType.wholeImage:
      _computeWholeImageAlpha(alpha);
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
    case MaskType.subject:
    case MaskType.sky:
    case MaskType.foreground:
      if (aiMap != null) {
        _computeSegmentAlpha(alpha, width, height, aiMap, mask.subject.feather);
      }
    case MaskType.depth:
      if (aiMap != null) {
        _computeDepthAlpha(alpha, width, height, aiMap, mask.depth);
      }
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

/// Alpha for a pixel [fraction] (0 at the shape's full-weight core, 1 at
/// the outer end of the feather) of the way through a feather band.
///
/// Smoothstep rather than the linear ramp every feather used until
/// 2026-09-10: a linear ramp has a slope discontinuity at both ends of the
/// band, and on a smooth subject (sky, skin) the eye picks that crease up
/// as a visible ring around a radial mask and as a hard rim on a colour
/// or luminance range. The S-curve leaves and arrives tangentially; it is
/// symmetric, so the midpoint stays at 0.5 and a feather still spans the
/// same distance. The linear gradient is not a feather and keeps its
/// straight ramp — that ramp *is* what the user drew.
double _featherAlpha(double fraction) {
  final t = fraction.clamp(0.0, 1.0);
  return 1.0 - t * t * (3.0 - 2.0 * t);
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
  // The fade's width as a fraction of the span, never quite zero: a hard
  // edge is a step no pixel grid can place, and a sliver of fade keeps it
  // from shimmering.
  final f = (g.feather / 100.0).clamp(0.02, 1.0);
  var p = 0;
  for (var y = 0; y < height; y++) {
    final ny = (y + 0.5) / height;
    for (var x = 0; x < width; x++, p++) {
      final nx = (x + 0.5) / width;
      final t = lenSq <= 0
          ? 0.0
          : ((nx - g.startX) * dx + (ny - g.startY) * dy) / lenSq;
      alpha[p] = (0.5 - (t - 0.5) / f).clamp(0.0, 1.0);
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
        alpha[p] = span <= 0 ? 0.0 : _featherAlpha((t - innerFrac) / span);
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
      alpha[i] = _featherAlpha((dist - core) / featherSpan);
    }
  }
}

/// No geometry, no reference — every pixel at full weight. The cheapest
/// possible mask; only exists so "affects the whole image" is a real,
/// selectable option alongside the shaped ones (e.g. to run a second,
/// independently-adjustable pass over the entire photo without needing a
/// gradient/brush/color-range shape to carry it).
void _computeWholeImageAlpha(Float32List alpha) {
  alpha.fillRange(0, alpha.length, 1.0);
}

/// Bilinearly samples [map] at the pixel grid of a [width] x [height]
/// render, returning 0..1 per pixel.
///
/// Both grids cover the same frame, so this is a pure rescale — the
/// half-pixel-center convention (`(x + 0.5) / width * mapWidth - 0.5`)
/// is the same one `colorize.dart` uses, and the same one OpenCV's
/// `INTER_LINEAR` uses, so a map and a render of equal size sample
/// straight through with no shift.
Float32List _sampleAiMap(AiMaskMap map, int width, int height) {
  final out = Float32List(width * height);
  final mw = map.width;
  final mh = map.height;
  if (mw <= 0 || mh <= 0) {
    return out;
  }
  final data = map.data;
  final xScale = mw / width;
  final yScale = mh / height;
  for (var y = 0; y < height; y++) {
    final sy = (y + 0.5) * yScale - 0.5;
    final y0 = sy.floor();
    final wy = sy - y0;
    final y0c = y0.clamp(0, mh - 1);
    final y1c = (y0 + 1).clamp(0, mh - 1);
    final row0 = y0c * mw;
    final row1 = y1c * mw;
    final rowOut = y * width;
    for (var x = 0; x < width; x++) {
      final sx = (x + 0.5) * xScale - 0.5;
      final x0 = sx.floor();
      final wx = sx - x0;
      final x0c = x0.clamp(0, mw - 1);
      final x1c = (x0 + 1).clamp(0, mw - 1);
      final top = data[row0 + x0c] * (1 - wx) + data[row0 + x1c] * wx;
      final bottom = data[row1 + x0c] * (1 - wx) + data[row1 + x1c] * wx;
      out[rowOut + x] = (top * (1 - wy) + bottom * wy) / 255.0;
    }
  }
  return out;
}

/// Subject/Sky/Foreground: the model's map *is* the mask, so this is only
/// the rescale. Their softness comes from the model — U-2-Net emits a
/// probability per pixel, and SAM's hard output is blurred a couple of
/// pixels before it ever gets here — which is why there is no tolerance or
/// feather knob to apply on top: there is no threshold being taken that a
/// user could usefully move.
/// The blur an AI mask's feather reaches at 100, as a fraction of the
/// frame's width.
const double aiMaskFeatherMaxFraction = 0.04;

void _computeSegmentAlpha(
  Float32List alpha,
  int width,
  int height,
  AiMaskMap map,
  double feather,
) {
  final sampled = _sampleAiMap(map, width, height);
  alpha.setAll(0, sampled);
  final radius =
      (feather.clamp(0.0, 100.0) / 100 * aiMaskFeatherMaxFraction * width)
          .round();
  if (radius > 0) {
    blurAlpha(alpha, width, height, radius);
  }
}

/// Softens [alpha] in place: a box blur of [radius] run twice, once per
/// axis each time, which is close to a Gaussian and costs the same
/// whatever the radius (a running sum per row and column).
void blurAlpha(Float32List alpha, int width, int height, int radius) {
  if (radius <= 0) {
    return;
  }
  final tmp = Float32List(alpha.length);
  for (var pass = 0; pass < 2; pass++) {
    // Rows.
    for (var y = 0; y < height; y++) {
      final row = y * width;
      var sum = 0.0;
      var count = 0;
      for (var x = 0; x <= radius && x < width; x++) {
        sum += alpha[row + x];
        count++;
      }
      for (var x = 0; x < width; x++) {
        tmp[row + x] = sum / count;
        final add = x + radius + 1;
        if (add < width) {
          sum += alpha[row + add];
          count++;
        }
        final drop = x - radius;
        if (drop >= 0) {
          sum -= alpha[row + drop];
          count--;
        }
      }
    }
    // Columns.
    for (var x = 0; x < width; x++) {
      var sum = 0.0;
      var count = 0;
      for (var y = 0; y <= radius && y < height; y++) {
        sum += tmp[y * width + x];
        count++;
      }
      for (var y = 0; y < height; y++) {
        alpha[y * width + x] = sum / count;
        final add = y + radius + 1;
        if (add < height) {
          sum += tmp[add * width + x];
          count++;
        }
        final drop = y - radius;
        if (drop >= 0) {
          sum -= tmp[drop * width + x];
          count--;
        }
      }
    }
  }
}

/// Depth: a band-pass over the depth map, full strength inside
/// [DepthGeometry.far]..[DepthGeometry.near] and fading out over
/// [DepthGeometry.feather] of the 0..1 depth range beyond each edge.
///
/// The map is sampled, not re-inferred — the whole point of caching it is
/// that dragging these three sliders costs a rescale and a lerp, not a
/// second pass through the model.
void _computeDepthAlpha(
  Float32List alpha,
  int width,
  int height,
  AiMaskMap map,
  DepthGeometry g,
) {
  final sampled = _sampleAiMap(map, width, height);
  final lo = g.far <= g.near ? g.far : g.near;
  final hi = g.far <= g.near ? g.near : g.far;
  final fade = (g.feather / 100.0).clamp(0.0, 1.0);
  for (var i = 0; i < alpha.length; i++) {
    final d = sampled[i];
    if (d >= lo && d <= hi) {
      alpha[i] = 1.0;
      continue;
    }
    if (fade <= 0) {
      alpha[i] = 0.0;
      continue;
    }
    final beyond = d < lo ? lo - d : d - hi;
    alpha[i] = beyond >= fade ? 0.0 : _featherAlpha(beyond / fade);
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
      alpha[i] = _featherAlpha((dist - core) / featherSpan);
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

/// Sentinel id for the always-present base layer — the whole photo, i.e.
/// the editor's existing global adjustments. Not a real [MaskLayer].
const imageMaskId = 'image';
