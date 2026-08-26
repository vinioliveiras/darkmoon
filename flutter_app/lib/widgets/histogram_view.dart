import 'package:flutter/material.dart';

import '../render/histogram.dart';
import '../theme.dart';

/// RGB histogram, additively blended (matching the Python app's
/// `HistogramWidget`: translucent red/green/blue fill areas over a dark
/// background, using plus/additive blending so overlaps read as brighter
/// mixed colors rather than muddying each other out).
class HistogramView extends StatelessWidget {
  const HistogramView({super.key, required this.histogram});

  final Histogram? histogram;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 108,
      decoration: BoxDecoration(
        color: DarkmoonColors.canvas,
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        size: Size.infinite,
        painter: _HistogramPainter(histogram),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  const _HistogramPainter(this.histogram);

  final Histogram? histogram;

  @override
  void paint(Canvas canvas, Size size) {
    final hist = histogram;
    if (hist == null) {
      return;
    }
    final maxValue = [
      hist.red.reduce((a, b) => a > b ? a : b),
      hist.green.reduce((a, b) => a > b ? a : b),
      hist.blue.reduce((a, b) => a > b ? a : b),
      1,
    ].reduce((a, b) => a > b ? a : b);

    final paint = Paint()..blendMode = BlendMode.plus;
    for (final channel in [
      (hist.red, const Color.fromARGB(140, 255, 90, 90)),
      (hist.green, const Color.fromARGB(140, 90, 255, 130)),
      (hist.blue, const Color.fromARGB(140, 100, 150, 255)),
    ]) {
      final (values, color) = channel;
      final path = Path()..moveTo(0, size.height);
      final step = size.width / values.length;
      for (var i = 0; i < values.length; i++) {
        final x = i * step;
        final h = (values[i] / maxValue) * (size.height - 4);
        path.lineTo(x, size.height - h);
      }
      path.lineTo(size.width, size.height);
      path.close();
      paint.color = color;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) =>
      oldDelegate.histogram != histogram;
}
