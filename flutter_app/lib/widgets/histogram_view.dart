import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../render/histogram.dart';
import '../theme.dart';

/// RGB histogram, additively blended (matching the Python app's
/// `HistogramWidget`: translucent red/green/blue fill areas over a dark
/// background, using plus/additive blending so overlaps read as brighter
/// mixed colors rather than muddying each other out).
///
/// With the clipping indicators every RAW editor's histogram has
/// (2026-09-11): a triangle in each top corner — shadows on the left,
/// highlights on the right — lit in the colour of the channels clipping
/// there (white when all three are), dim when nothing clips; hover for
/// the fraction.
class HistogramView extends StatelessWidget {
  const HistogramView({super.key, required this.histogram});

  final Histogram? histogram;

  /// Below this fraction of the frame a channel is not reported as
  /// clipping — a few stray specular pixels are not a blown highlight.
  static const double clippingReportThreshold = 0.0001;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hist = histogram;
    return Container(
      height: 108,
      decoration: BoxDecoration(
        color: DarkmoonColors.canvas,
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          CustomPaint(size: Size.infinite, painter: _HistogramPainter(hist)),
          if (hist != null && hist.pixelCount > 0) ...[
            Positioned(
              top: 4,
              left: 4,
              child: _ClippingIndicator(
                fractions: [
                  for (var c = 0; c < 3; c++) hist.clippedLowFraction(c),
                ],
                pointsLeft: true,
                message: (percent) => percent == null
                    ? l10n.histogramNoShadowClipping
                    : l10n.histogramShadowClipping(percent),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: _ClippingIndicator(
                fractions: [
                  for (var c = 0; c < 3; c++) hist.clippedHighFraction(c),
                ],
                pointsLeft: false,
                message: (percent) => percent == null
                    ? l10n.histogramNoHighlightClipping
                    : l10n.histogramHighlightClipping(percent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One corner triangle. [fractions] is the clipped fraction per channel
/// (R, G, B); the triangle takes the additive colour of the channels over
/// [HistogramView.clippingReportThreshold], white for all three.
class _ClippingIndicator extends StatelessWidget {
  const _ClippingIndicator({
    required this.fractions,
    required this.pointsLeft,
    required this.message,
  });

  final List<double> fractions;
  final bool pointsLeft;
  final String Function(String? percent) message;

  @override
  Widget build(BuildContext context) {
    final clipping = [
      for (final f in fractions) f >= HistogramView.clippingReportThreshold,
    ];
    final any = clipping.contains(true);
    final worst = fractions.reduce((a, b) => a > b ? a : b);
    final Color color;
    if (!any) {
      color = DarkmoonColors.textMuted.withValues(alpha: 0.35);
    } else if (clipping.every((c) => c)) {
      color = Colors.white;
    } else {
      color = Color.fromARGB(
        255,
        clipping[0] ? 255 : 40,
        clipping[1] ? 255 : 40,
        clipping[2] ? 255 : 40,
      );
    }
    final percent = any
        ? (worst * 100).toStringAsFixed(worst >= 0.01 ? 1 : 2)
        : null;
    return Tooltip(
      message: message(percent),
      child: CustomPaint(
        size: const Size(10, 10),
        painter: _TrianglePainter(color: color, pointsLeft: pointsLeft),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color, required this.pointsLeft});

  final Color color;
  final bool pointsLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final path = pointsLeft
        ? (Path()
            ..moveTo(0, 0)
            ..lineTo(size.width, 0)
            ..lineTo(0, size.height)
            ..close())
        : (Path()
            ..moveTo(size.width, 0)
            ..lineTo(0, 0)
            ..lineTo(size.width, size.height)
            ..close());
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointsLeft != pointsLeft;
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
