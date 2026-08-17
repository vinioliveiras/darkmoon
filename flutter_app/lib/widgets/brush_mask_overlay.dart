import 'package:flutter/material.dart';

import '../render/mask.dart';
import '../theme.dart';

/// Freehand brush painting for a Brush mask, drawn directly over the
/// displayed image. Meant to be placed as a sibling of the `Image` widget
/// inside the same `SizedBox.expand` — since it lives inside the same
/// `InteractiveViewer` subtree as the image, it pans/zooms together with
/// it for free, no manual transform math needed.
///
/// Shows a live, semi-transparent preview of every dab painted so far
/// (committed strokes + the one currently being dragged) so it's obvious
/// where the mask actually covers, the same idea as the gradient masks'
/// shaded overlay. The real per-pixel mask ([computeMaskAlpha]) is
/// recomputed from the same stroke data at render time — this preview
/// approximates it with plain circles for speed, not exact math.
///
/// [imageWidth]/[imageHeight] are the displayed image's own pixel
/// dimensions (any resolution tier works, only their aspect ratio
/// matters) — needed to work out where `BoxFit.contain` actually placed
/// the image within [containerSize], since normalized mask/brush
/// coordinates are relative to the image, not the (usually letterboxed)
/// container.
class BrushMaskOverlay extends StatefulWidget {
  const BrushMaskOverlay({
    super.key,
    required this.containerSize,
    required this.imageWidth,
    required this.imageHeight,
    required this.mask,
    required this.brushRadius,
    required this.brushHardness,
    required this.brushErase,
    required this.onChanged,
    required this.onChangeEnd,
    this.showOverlay = true,
    this.overlayOpacity = 0.4,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;
  final MaskLayer mask;

  /// Normalized to image width, same convention as [RadialGradientGeometry.radius].
  final double brushRadius;
  final double brushHardness;
  final bool brushErase;
  final ValueChanged<MaskLayer> onChanged;
  final ValueChanged<MaskLayer> onChangeEnd;

  /// Whether painted strokes are shown as a shaded overlay — when false,
  /// only the hover cursor ring (needed to place the next dab) still
  /// draws, matching the other mask overlays' visibility toggle.
  final bool showOverlay;

  /// How opaque painted strokes' shading is, 0..1 — user-adjustable, same
  /// idea as [GradientMaskOverlay.overlayOpacity]. The hover cursor ring
  /// stays at full opacity regardless, since it's UI chrome, not shading.
  final double overlayOpacity;

  @override
  State<BrushMaskOverlay> createState() => _BrushMaskOverlayState();
}

/// Minimum on-screen distance (as a fraction of the brush's on-screen
/// radius) between consecutive stored dabs — dense enough to avoid gaps
/// in the stroke, sparse enough to keep the point list small.
const _minDabSpacingFraction = 0.25;

class _BrushMaskOverlayState extends State<BrushMaskOverlay> {
  final List<Offset> _liveStroke = [];
  Offset? _hoverLocal;

  Rect _imageRect() {
    final imageAspect = widget.imageWidth / widget.imageHeight;
    final size = widget.containerSize;
    final containerAspect = size.width / size.height;
    double w, h;
    if (containerAspect > imageAspect) {
      h = size.height;
      w = h * imageAspect;
    } else {
      w = size.width;
      h = w / imageAspect;
    }
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
  }

  BrushPoint _toNormalized(Offset local, Rect r) =>
      BrushPoint((local.dx - r.left) / r.width, (local.dy - r.top) / r.height);

  BrushStroke _strokeFrom(List<Offset> screenPoints, Rect imageRect) =>
      BrushStroke(
        points: [
          for (final point in screenPoints) _toNormalized(point, imageRect),
        ],
        radius: widget.brushRadius,
        hardness: widget.brushHardness,
        erase: widget.brushErase,
      );

  void _startStroke(Offset local) {
    _liveStroke
      ..clear()
      ..add(local);
  }

  void _updateStroke(Offset local, Rect imageRect) {
    if (_liveStroke.isEmpty) {
      return;
    }
    final radiusPx = widget.brushRadius * imageRect.width;
    final minSpacing = radiusPx * _minDabSpacingFraction;
    if ((local - _liveStroke.last).distance >= minSpacing) {
      _liveStroke.add(local);
    }
    widget.onChanged(
      widget.mask.copyWith(
        brush: widget.mask.brush.copyWith(
          strokes: [
            ...widget.mask.brush.strokes,
            _strokeFrom(_liveStroke, imageRect),
          ],
        ),
      ),
    );
  }

  void _endStroke(Rect imageRect) {
    if (_liveStroke.isEmpty) {
      return;
    }
    widget.onChangeEnd(
      widget.mask.copyWith(
        brush: widget.mask.brush.copyWith(
          strokes: [
            ...widget.mask.brush.strokes,
            _strokeFrom(_liveStroke, imageRect),
          ],
        ),
      ),
    );
    _liveStroke.clear();
  }

  @override
  Widget build(BuildContext context) {
    final imageRect = _imageRect();
    return MouseRegion(
      onHover: (event) => setState(() => _hoverLocal = event.localPosition),
      onExit: (_) => setState(() => _hoverLocal = null),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _startStroke(details.localPosition),
        onPanUpdate: (details) =>
            _updateStroke(details.localPosition, imageRect),
        onPanEnd: (_) => _endStroke(imageRect),
        child: CustomPaint(
          size: widget.containerSize,
          painter: _BrushPreviewPainter(
            // widget.mask.brush.strokes already includes the in-progress
            // stroke as its last element while dragging — onChanged
            // (called from _updateStroke) appends it live — so this alone
            // covers both committed strokes and the one being dragged.
            strokes: widget.showOverlay ? widget.mask.brush.strokes : const [],
            imageRect: imageRect,
            radiusPx: widget.brushRadius * imageRect.width,
            cursor: _hoverLocal,
            overlayOpacity: widget.overlayOpacity,
          ),
        ),
      ),
    );
  }
}

class _BrushPreviewPainter extends CustomPainter {
  const _BrushPreviewPainter({
    required this.strokes,
    required this.imageRect,
    required this.radiusPx,
    required this.cursor,
    required this.overlayOpacity,
  });

  /// Every stroke the mask currently has, including the one still being
  /// dragged (see the comment at this painter's construction site) —
  /// shown as a persistent shaded overlay (toggleable via
  /// [BrushMaskOverlay.showOverlay]), the same idea as the gradient masks'
  /// shaded coverage area, so a painted-then-released brush mask still
  /// shows where it covers instead of only being visible in the rendered
  /// image itself.
  final List<BrushStroke> strokes;
  final Rect imageRect;
  final double radiusPx;
  final Offset? cursor;
  final double overlayOpacity;

  void _paintDabs(
    Canvas canvas,
    List<Offset> points,
    double radius,
    double hardness,
    bool eraseStroke,
  ) {
    final blur = (radius * (1 - hardness)).clamp(0.0, radius);
    final paint = Paint()
      ..color = DarkmoonColors.accent.withValues(alpha: overlayOpacity)
      ..blendMode = eraseStroke ? BlendMode.clear : BlendMode.srcOver
      ..maskFilter = blur > 0
          ? MaskFilter.blur(BlurStyle.normal, blur / 2)
          : null;
    for (final point in points) {
      canvas.drawCircle(point, radius, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isNotEmpty) {
      canvas.saveLayer(Offset.zero & size, Paint());
      for (final stroke in strokes) {
        final points = [
          for (final p in stroke.points)
            Offset(
              imageRect.left + p.x * imageRect.width,
              imageRect.top + p.y * imageRect.height,
            ),
        ];
        _paintDabs(
          canvas,
          points,
          stroke.radius * imageRect.width,
          stroke.hardness,
          stroke.erase,
        );
      }
      canvas.restore();
    }

    final hoverPoint = cursor;
    if (hoverPoint != null) {
      canvas.drawCircle(
        hoverPoint,
        radiusPx,
        Paint()
          ..color = DarkmoonColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BrushPreviewPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.imageRect != imageRect ||
      oldDelegate.radiusPx != radiusPx ||
      oldDelegate.cursor != cursor ||
      oldDelegate.overlayOpacity != overlayOpacity;
}
