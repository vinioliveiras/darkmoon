import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../render/hsl.dart';

/// A Lightroom-style color-grading wheel: drag (or click) anywhere to set
/// hue (angle) and saturation (distance from center) at once; double-tap
/// snaps back to dead center (no tint), matching the sliders'
/// double-tap-to-reset convention.
///
/// [onChanged] fires continuously while dragging (for a live low-res
/// preview, matching [SliderRow]/[ToneCurveEditor]'s pattern);
/// [onChangeEnd] fires once the gesture finishes (for the full-quality
/// render + catalog save).
class ColorWheel extends StatefulWidget {
  const ColorWheel({
    super.key,
    required this.hue,
    required this.saturation,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double hue; // degrees, 0..360
  final double saturation; // 0..100
  final void Function(double hue, double saturation) onChanged;
  final void Function(double hue, double saturation) onChangeEnd;

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  Offset? _lastLocal;
  Size? _lastSize;

  (double, double) _fromLocal(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final delta = local - center;
    final dist = delta.distance.clamp(0.0, radius);
    var angle = math.atan2(delta.dy, delta.dx) * 180 / math.pi;
    if (angle < 0) {
      angle += 360;
    }
    return (angle, radius == 0 ? 0.0 : (dist / radius) * 100);
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    _lastLocal = details.localPosition;
    _lastSize = size;
    final (hue, saturation) = _fromLocal(details.localPosition, size);
    widget.onChanged(hue, saturation);
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    _lastLocal = details.localPosition;
    _lastSize = size;
    final (hue, saturation) = _fromLocal(details.localPosition, size);
    widget.onChanged(hue, saturation);
  }

  void _handlePanEnd(DragEndDetails details) {
    final local = _lastLocal;
    final size = _lastSize;
    if (local == null || size == null) {
      return;
    }
    final (hue, saturation) = _fromLocal(local, size);
    widget.onChangeEnd(hue, saturation);
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    final (hue, saturation) = _fromLocal(details.localPosition, size);
    widget.onChanged(hue, saturation);
    widget.onChangeEnd(hue, saturation);
  }

  void _handleDoubleTap() {
    widget.onChanged(widget.hue, 0);
    widget.onChangeEnd(widget.hue, 0);
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
            onDoubleTap: _handleDoubleTap,
            child: CustomPaint(
              painter: _ColorWheelPainter(
                hue: widget.hue,
                saturation: widget.saturation,
              ),
              size: size,
            ),
          );
        },
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  const _ColorWheelPainter({required this.hue, required this.saturation});

  final double hue;
  final double saturation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final hueColors = List.generate(13, (i) {
      final rgb = hslToRgb(i * 30.0, 1.0, 0.5);
      return Color.fromARGB(
        255,
        (rgb[0] * 255).round(),
        (rgb[1] * 255).round(),
        (rgb[2] * 255).round(),
      );
    });
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: hueColors,
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    // Apple's own color wheels (Final Cut, Photos) fade toward a neutral
    // mid-gray at the center rather than white — 0 saturation means "no
    // tint" (gray), not "lighter," so the wheel's own center should read
    // as neutral instead of blown out.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF8A8A8E), Color(0x008A8A8E)],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final angleRad = hue * math.pi / 180;
    final dist = (saturation / 100).clamp(0.0, 1.0) * radius;
    final puckCenter =
        center + Offset(math.cos(angleRad), math.sin(angleRad)) * dist;

    // A thin guide line from center to the puck — the vector itself
    // (direction = hue, length = saturation) is legible at a glance, the
    // same affordance Final Cut's wheels use.
    if (dist > 0.5) {
      canvas.drawLine(
        center,
        puckCenter,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.2,
      );
    }

    canvas.drawCircle(
      puckCenter,
      7,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(puckCenter, 6, Paint()..color = Colors.white);
    canvas.drawCircle(
      puckCenter,
      6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) =>
      oldDelegate.hue != hue || oldDelegate.saturation != saturation;
}
