import 'package:flutter/material.dart';

/// Tap-to-sample surface for a Color Range mask — clicking anywhere on
/// the image picks that point's color as the mask's reference color.
/// Unlike the gradient/brush overlays this needs no on-canvas drawing of
/// its own; the panel's color swatch and tolerance/feather sliders are
/// enough to show the current selection.
class ColorRangeOverlay extends StatelessWidget {
  const ColorRangeOverlay({
    super.key,
    required this.containerSize,
    required this.imageWidth,
    required this.imageHeight,
    required this.onSample,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;

  /// Normalized (0..1) image coordinates of the tapped point.
  final void Function(double nx, double ny) onSample;

  Rect _imageRect() {
    final imageAspect = imageWidth / imageHeight;
    final containerAspect = containerSize.width / containerSize.height;
    double w, h;
    if (containerAspect > imageAspect) {
      h = containerSize.height;
      w = h * imageAspect;
    } else {
      w = containerSize.width;
      h = w / imageAspect;
    }
    return Rect.fromLTWH(
      (containerSize.width - w) / 2,
      (containerSize.height - h) / 2,
      w,
      h,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final rect = _imageRect();
          final nx = ((details.localPosition.dx - rect.left) / rect.width)
              .clamp(0.0, 1.0);
          final ny = ((details.localPosition.dy - rect.top) / rect.height)
              .clamp(0.0, 1.0);
          onSample(nx, ny);
        },
      ),
    );
  }
}
