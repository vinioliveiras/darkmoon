import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../render/tone_curve.dart';
import '../theme.dart';

/// Meridian-style Tone Curve graph: drag a point to reshape the curve,
/// (left-)tap empty space to add a point, right-click (or long-press, for
/// touch/trackpad) a point to remove it — endpoints excepted, since they
/// anchor the curve's black/white ends.
///
/// [onChanged] fires continuously while dragging (for a live low-res
/// preview, matching [SliderRow]'s pattern); [onChangeEnd] fires once the
/// gesture finishes (for the full-quality render + catalog save).
class ToneCurveEditor extends StatefulWidget {
  const ToneCurveEditor({
    super.key,
    required this.points,
    required this.onChanged,
    required this.onChangeEnd,
    this.lineColor = DarkmoonColors.accent,
  });

  final List<CurvePoint> points;
  final ValueChanged<List<CurvePoint>> onChanged;
  final ValueChanged<List<CurvePoint>> onChangeEnd;

  /// Curve/handle color — the app accent for the master Tone Curve, or a
  /// channel color (red/green/blue) when reused for the Color Curve panel.
  final Color lineColor;

  @override
  State<ToneCurveEditor> createState() => _ToneCurveEditorState();
}

const _hitRadius = 16.0;
const _minPointSpacing = 0.02;
const _maxPoints = 12;

/// Margin, in pixels, the plotted 0..1 curve space is inset from the
/// widget's own edges — real bug fixed 2026-09-01: an endpoint sitting
/// exactly at x=0/1 or y=0/1 put its handle circle's centre right on the
/// widget's boundary, so the section card's rounded-corner clip (or any
/// other ancestor clip) cut off roughly half of it at every corner.
/// [_handlePaintRadius] (the biggest thing drawn at a point) plus a
/// couple of px of breathing room is enough for the whole handle to
/// always render fully on-screen, at every point position.
const _plotInset = 8.0;

class _ToneCurveEditorState extends State<ToneCurveEditor> {
  int? _activeIndex;

  List<CurvePoint> get _sorted =>
      [...widget.points]..sort((a, b) => a.x.compareTo(b.x));

  Offset _toLocal(CurvePoint point, Size size) {
    final usableW = size.width - 2 * _plotInset;
    final usableH = size.height - 2 * _plotInset;
    return Offset(
      _plotInset + point.x * usableW,
      _plotInset + (1 - point.y) * usableH,
    );
  }

  CurvePoint _toPoint(Offset local, Size size) {
    final usableW = size.width - 2 * _plotInset;
    final usableH = size.height - 2 * _plotInset;
    return CurvePoint(
      ((local.dx - _plotInset) / usableW).clamp(0.0, 1.0),
      (1 - (local.dy - _plotInset) / usableH).clamp(0.0, 1.0),
    );
  }

  int? _nearestPointIndex(Offset local, Size size, List<CurvePoint> points) {
    var closestIndex = -1;
    var closestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = (_toLocal(points[i], size) - local).distance;
      if (distance < closestDistance) {
        closestDistance = distance;
        closestIndex = i;
      }
    }
    return closestDistance <= _hitRadius ? closestIndex : null;
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    _activeIndex = _nearestPointIndex(details.localPosition, size, _sorted);
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    final index = _activeIndex;
    if (index == null) {
      return;
    }
    final points = _sorted;
    final isEndpoint = index == 0 || index == points.length - 1;
    var next = _toPoint(details.localPosition, size);
    if (isEndpoint) {
      // Endpoints anchor the curve's x-domain — only their output (y) moves.
      next = CurvePoint(points[index].x, next.y);
    } else {
      final minX = points[index - 1].x + _minPointSpacing;
      final maxX = points[index + 1].x - _minPointSpacing;
      next = CurvePoint(next.x.clamp(minX, maxX), next.y);
    }
    final updated = [...points];
    updated[index] = next;
    widget.onChanged(updated);
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_activeIndex != null) {
      widget.onChangeEnd(_sorted);
    }
    _activeIndex = null;
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    final points = _sorted;
    if (_nearestPointIndex(details.localPosition, size, points) != null ||
        points.length >= _maxPoints) {
      return;
    }
    final updated = [...points, _toPoint(details.localPosition, size)]
      ..sort((a, b) => a.x.compareTo(b.x));
    widget.onChanged(updated);
    widget.onChangeEnd(updated);
  }

  /// Removes whichever point is nearest [local] — endpoints excepted,
  /// since they anchor the curve. Shared by long-press (touch/trackpad)
  /// and right-click (mouse), the two ways to delete a point.
  void _removeNearestPoint(Offset local, Size size) {
    final points = _sorted;
    final index = _nearestPointIndex(local, size, points);
    if (index == null || index == 0 || index == points.length - 1) {
      return;
    }
    final updated = [...points]..removeAt(index);
    widget.onChanged(updated);
    widget.onChangeEnd(updated);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (details) => _handlePanStart(details, size),
            onPanUpdate: (details) => _handlePanUpdate(details, size),
            onPanEnd: _handlePanEnd,
            onTapUp: (details) => _handleTapUp(details, size),
            onLongPressStart: (details) =>
                _removeNearestPoint(details.localPosition, size),
            onSecondaryTapUp: (details) =>
                _removeNearestPoint(details.localPosition, size),
            child: CustomPaint(
              painter: _ToneCurvePainter(
                points: _sorted,
                lineColor: widget.lineColor,
              ),
              size: size,
            ),
          );
        },
      ),
    );
  }
}

class _ToneCurvePainter extends CustomPainter {
  const _ToneCurvePainter({required this.points, required this.lineColor});

  final List<CurvePoint> points;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is drawn inset from the widget's own edges by
    // [_plotInset] — grid, curve and handles alike — so an endpoint
    // handle sitting at the very corner of the *plotted* range still has
    // a few px of margin before the widget's actual boundary (see
    // [_plotInset]'s doc for the corner-clipping bug this fixes).
    final plot = Rect.fromLTWH(
      _plotInset,
      _plotInset,
      size.width - 2 * _plotInset,
      size.height - 2 * _plotInset,
    );

    final gridPaint = Paint()
      ..color = DarkmoonColors.border
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = plot.left + plot.width * i / 4;
      final y = plot.top + plot.height * i / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    canvas.drawRect(plot, gridPaint..style = PaintingStyle.stroke);

    final diagonalPaint = Paint()
      ..color = DarkmoonColors.textMuted.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.top),
      diagonalPaint,
    );

    final lut = buildToneCurveLut(points);
    final curvePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path();
    for (var i = 0; i < 256; i++) {
      final x = plot.left + plot.width * i / 255;
      final y = plot.top + plot.height * (1 - lut[i] / 255);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, curvePaint);

    final handleFill = Paint()..color = DarkmoonColors.surfaceRaised;
    final handleBorder = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final point in points) {
      final center = Offset(
        plot.left + point.x * plot.width,
        plot.top + (1 - point.y) * plot.height,
      );
      canvas.drawCircle(center, 5, handleFill);
      canvas.drawCircle(center, 5, handleBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _ToneCurvePainter oldDelegate) =>
      // Real bug fixed 2026-09-02: `_ToneCurveEditorState._sorted` builds a
      // brand-new List every call (`[...widget.points]..sort(...)`), so a
      // plain `!=` (identity) here was always true regardless of whether
      // the curve actually changed — every drag of an unrelated slider
      // repainted this and recomputed its 256-sample LUT for nothing.
      // CurvePoint has value equality, so listEquals does a real content
      // comparison instead.
      !listEquals(oldDelegate.points, points) ||
      oldDelegate.lineColor != lineColor;
}
