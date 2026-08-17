import 'package:flutter/material.dart';

import '../render/crop_transform.dart';
import '../theme.dart';

/// A common aspect-ratio choice for the Crop tool's ratio picker —
/// [ratio] is width/height, null means "free" (unconstrained).
class CropAspectPreset {
  const CropAspectPreset(this.label, this.ratio);

  final String label;
  final double? ratio;
}

const cropAspectPresets = [
  CropAspectPreset('Free', null),
  CropAspectPreset('1:1', 1.0),
  CropAspectPreset('4:3', 4 / 3),
  CropAspectPreset('3:2', 3 / 2),
  CropAspectPreset('16:9', 16 / 9),
  CropAspectPreset('5:4', 5 / 4),
];

enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight, move }

const _handleHitRadius = 20.0;

/// Draggable crop rectangle, shown over the (already straightened/
/// keystoned) preview image while the Crop tool is active — same
/// `BoxFit.contain` letterbox math as the mask overlays, applied to
/// [params]'s crop rect instead of a mask's geometry.
///
/// [lockedAspectRatio], if set, constrains every drag to keep that
/// width/height ratio (Lightroom's aspect-ratio-picker behavior);
/// otherwise the four corners move independently.
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.containerSize,
    required this.imageWidth,
    required this.imageHeight,
    required this.params,
    required this.onChanged,
    required this.onChangeEnd,
    this.lockedAspectRatio,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;
  final CropTransformParams params;
  final ValueChanged<CropTransformParams> onChanged;
  final ValueChanged<CropTransformParams> onChangeEnd;
  final double? lockedAspectRatio;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  _CropHandle? _active;
  Offset _dragStartLocal = Offset.zero;
  CropTransformParams _dragStartParams = const CropTransformParams();

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

  Rect _cropRectLocal(Rect imageRect) => Rect.fromLTRB(
    imageRect.left + widget.params.cropLeft * imageRect.width,
    imageRect.top + widget.params.cropTop * imageRect.height,
    imageRect.left + widget.params.cropRight * imageRect.width,
    imageRect.top + widget.params.cropBottom * imageRect.height,
  );

  void _handlePanStart(DragStartDetails details, Rect imageRect) {
    _dragStartLocal = details.localPosition;
    _dragStartParams = widget.params;
    final cropRect = _cropRectLocal(imageRect);
    final corners = {
      _CropHandle.topLeft: cropRect.topLeft,
      _CropHandle.topRight: cropRect.topRight,
      _CropHandle.bottomLeft: cropRect.bottomLeft,
      _CropHandle.bottomRight: cropRect.bottomRight,
    };
    _CropHandle? closest;
    var closestDist = double.infinity;
    for (final entry in corners.entries) {
      final dist = (entry.value - _dragStartLocal).distance;
      if (dist < closestDist) {
        closestDist = dist;
        closest = entry.key;
      }
    }
    if (closestDist <= _handleHitRadius) {
      _active = closest;
    } else if (cropRect.contains(_dragStartLocal)) {
      _active = _CropHandle.move;
    } else {
      _active = null;
    }
  }

  CropTransformParams _applyDrag(Offset local, Rect imageRect) {
    final dx = (local.dx - _dragStartLocal.dx) / imageRect.width;
    final dy = (local.dy - _dragStartLocal.dy) / imageRect.height;
    final start = _dragStartParams;
    switch (_active) {
      case _CropHandle.move:
        final width = start.cropRight - start.cropLeft;
        final height = start.cropBottom - start.cropTop;
        var left = (start.cropLeft + dx).clamp(0.0, 1.0 - width);
        var top = (start.cropTop + dy).clamp(0.0, 1.0 - height);
        return start.copyWith(
          cropLeft: left,
          cropTop: top,
          cropRight: left + width,
          cropBottom: top + height,
        );
      case _CropHandle.topLeft:
        return _dragCorner(
          start,
          newLeft: start.cropLeft + dx,
          newTop: start.cropTop + dy,
        );
      case _CropHandle.topRight:
        return _dragCorner(
          start,
          newRight: start.cropRight + dx,
          newTop: start.cropTop + dy,
        );
      case _CropHandle.bottomLeft:
        return _dragCorner(
          start,
          newLeft: start.cropLeft + dx,
          newBottom: start.cropBottom + dy,
        );
      case _CropHandle.bottomRight:
        return _dragCorner(
          start,
          newRight: start.cropRight + dx,
          newBottom: start.cropBottom + dy,
        );
      case null:
        return start;
    }
  }

  /// Applies one corner's drag, clamping to the frame and (if
  /// [CropOverlay.lockedAspectRatio] is set) re-deriving the opposite
  /// dimension to keep that ratio — anchored at the *opposite* corner, so
  /// dragging top-left keeps bottom-right fixed, matching how every other
  /// crop tool's aspect lock behaves.
  CropTransformParams _dragCorner(
    CropTransformParams start, {
    double? newLeft,
    double? newTop,
    double? newRight,
    double? newBottom,
  }) {
    var left = (newLeft ?? start.cropLeft).clamp(0.0, 1.0);
    var top = (newTop ?? start.cropTop).clamp(0.0, 1.0);
    var right = (newRight ?? start.cropRight).clamp(0.0, 1.0);
    var bottom = (newBottom ?? start.cropBottom).clamp(0.0, 1.0);

    final ratio = widget.lockedAspectRatio;
    if (ratio != null) {
      final imageAspect = widget.imageWidth / widget.imageHeight;
      // The crop rect is normalized 0..1 per-axis, so a target on-image
      // aspect ratio maps to a different normalized-space ratio unless
      // the image itself is square — correct for that here.
      final normalizedRatio = ratio / imageAspect;
      final width = right - left;
      final height = bottom - top;
      if (newLeft != null || newTop != null) {
        // Anchored at bottom-right: recompute left/top from the new
        // height (or width, whichever the drag actually changed) so the
        // ratio holds.
        if (newLeft != null) {
          top = bottom - width / normalizedRatio;
        } else {
          left = right - height * normalizedRatio;
        }
      } else {
        if (newRight != null) {
          bottom = top + width / normalizedRatio;
        } else {
          right = left + height * normalizedRatio;
        }
      }
    }

    if (right - left < 0.02) {
      if (newLeft != null) {
        left = right - 0.02;
      } else {
        right = left + 0.02;
      }
    }
    if (bottom - top < 0.02) {
      if (newTop != null) {
        top = bottom - 0.02;
      } else {
        bottom = top + 0.02;
      }
    }

    return start.copyWith(
      cropLeft: left.clamp(0.0, 1.0),
      cropTop: top.clamp(0.0, 1.0),
      cropRight: right.clamp(0.0, 1.0),
      cropBottom: bottom.clamp(0.0, 1.0),
    );
  }

  void _handlePanUpdate(DragUpdateDetails details, Rect imageRect) {
    if (_active == null) {
      return;
    }
    widget.onChanged(_applyDrag(details.localPosition, imageRect));
  }

  void _handlePanEnd(Rect imageRect) {
    if (_active == null) {
      return;
    }
    widget.onChangeEnd(_applyDrag(_dragStartLocal, imageRect));
    _active = null;
  }

  @override
  Widget build(BuildContext context) {
    final imageRect = _imageRect();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) => _handlePanStart(details, imageRect),
      onPanUpdate: (details) => _handlePanUpdate(details, imageRect),
      onPanEnd: (_) => _handlePanEnd(imageRect),
      child: CustomPaint(
        size: widget.containerSize,
        painter: _CropPainter(
          imageRect: imageRect,
          cropRect: _cropRectLocal(imageRect),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({required this.imageRect, required this.cropRect});

  final Rect imageRect;
  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    // Darkens everything outside the crop rect — the standard "shade the
    // discarded area" crop-tool convention.
    final scrimPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final fullPath = Path()..addRect(Offset.zero & size);
    final cropPath = Path()..addRect(cropRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, fullPath, cropPath),
      scrimPaint,
    );

    // Rule-of-thirds guide lines inside the crop rect.
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = cropRect.left + cropRect.width * i / 3;
      canvas.drawLine(
        Offset(x, cropRect.top),
        Offset(x, cropRect.bottom),
        gridPaint,
      );
      final y = cropRect.top + cropRect.height * i / 3;
      canvas.drawLine(
        Offset(cropRect.left, y),
        Offset(cropRect.right, y),
        gridPaint,
      );
    }

    canvas.drawRect(
      cropRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    for (final corner in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      canvas.drawCircle(corner, 6, Paint()..color = DarkmoonColors.accent);
      canvas.drawCircle(
        corner,
        6,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect || oldDelegate.cropRect != cropRect;
}
