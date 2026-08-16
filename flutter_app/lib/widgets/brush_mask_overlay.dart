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
            liveStroke: _liveStroke,
            radiusPx: widget.brushRadius * imageRect.width,
            hardness: widget.brushHardness,
            erase: widget.brushErase,
            cursor: _hoverLocal,
          ),
        ),
      ),
    );
  }
}

class _BrushPreviewPainter extends CustomPainter {
  const _BrushPreviewPainter({
    required this.liveStroke,
    required this.radiusPx,
    required this.hardness,
    required this.erase,
    required this.cursor,
  });

  final List<Offset> liveStroke;
  final double radiusPx;
  final double hardness;
  final bool erase;
  final Offset? cursor;

  void _paintDabs(
    Canvas canvas,
    List<Offset> points,
    double radius,
    bool eraseStroke,
  ) {
    final blur = (radius * (1 - hardness)).clamp(0.0, radius);
    final paint = Paint()
      ..color = DarkmoonColors.accent.withValues(alpha: 0.4)
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
    // Committed strokes already show up in the rendered image itself
    // (each one triggers a real re-render when the drag that made it
    // ends) — only the stroke still being dragged needs an approximate
    // preview here, ahead of the next debounced render.
    if (liveStroke.isNotEmpty) {
      canvas.saveLayer(Offset.zero & size, Paint());
      _paintDabs(canvas, liveStroke, radiusPx, erase);
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
      oldDelegate.liveStroke != liveStroke ||
      oldDelegate.radiusPx != radiusPx ||
      oldDelegate.hardness != hardness ||
      oldDelegate.cursor != cursor;
}
