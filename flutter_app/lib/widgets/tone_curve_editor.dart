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

class _ToneCurveEditorState extends State<ToneCurveEditor> {
  int? _activeIndex;

  List<CurvePoint> get _sorted =>
      [...widget.points]..sort((a, b) => a.x.compareTo(b.x));

  Offset _toLocal(CurvePoint point, Size size) =>
      Offset(point.x * size.width, (1 - point.y) * size.height);

  CurvePoint _toPoint(Offset local, Size size) => CurvePoint(
    (local.dx / size.width).clamp(0.0, 1.0),
    (1 - local.dy / size.height).clamp(0.0, 1.0),
  );

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
    final gridPaint = Paint()
      ..color = DarkmoonColors.border
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawRect(
      Offset.zero & size,
      gridPaint..style = PaintingStyle.stroke,
    );

    final diagonalPaint = Paint()
      ..color = DarkmoonColors.textMuted.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, 0),
      diagonalPaint,
    );

    final lut = buildToneCurveLut(points);
    final curvePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path();
    for (var i = 0; i < 256; i++) {
      final x = size.width * i / 255;
      final y = size.height * (1 - lut[i] / 255);
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
      final center = Offset(point.x * size.width, (1 - point.y) * size.height);
      canvas.drawCircle(center, 5, handleFill);
      canvas.drawCircle(center, 5, handleBorder);
    }
  }

  @override
  bool shouldRepaint(covariant _ToneCurvePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.lineColor != lineColor;
}
