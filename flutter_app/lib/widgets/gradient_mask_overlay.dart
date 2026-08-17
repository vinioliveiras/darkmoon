import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../render/mask.dart';
import '../theme.dart';

/// Default opacity for the shaded overlay on the mask's full-effect side —
/// tinted, not solid, so the image underneath stays visible while editing.
/// User-adjustable via [GradientMaskOverlay.overlayOpacity]; this is just
/// its fallback.
const _defaultShadeAlpha = 0.32;

/// Draggable on-canvas handles for editing a Linear or Radial Gradient
/// mask's geometry, drawn directly over the displayed image. Meant to be
/// placed as a sibling of the `Image` widget inside the same
/// `SizedBox.expand` — since it lives inside the same `InteractiveViewer`
/// subtree as the image, it pans/zooms together with it for free, no
/// manual transform math needed.
///
/// [imageWidth]/[imageHeight] are the displayed image's own pixel
/// dimensions (any resolution tier works, only their aspect ratio
/// matters) — needed to work out where `BoxFit.contain` actually placed
/// the image within [containerSize], since normalized mask coordinates
/// are relative to the image, not the (usually letterboxed) container.
class GradientMaskOverlay extends StatefulWidget {
  const GradientMaskOverlay({
    super.key,
    required this.containerSize,
    required this.imageWidth,
    required this.imageHeight,
    required this.mask,
    required this.onChanged,
    required this.onChangeEnd,
    this.showOverlay = true,
    this.overlayOpacity = _defaultShadeAlpha,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;
  final MaskLayer mask;
  final ValueChanged<MaskLayer> onChanged;
  final ValueChanged<MaskLayer> onChangeEnd;

  /// Whether the shaded coverage area + handles are drawn — when false,
  /// drag handling still works (invisibly), so hiding the overlay doesn't
  /// also disable editing.
  final bool showOverlay;

  /// How opaque the shaded coverage area is, 0..1 — user-adjustable so a
  /// bright white wash doesn't obscure the photo while judging a mask's
  /// effect. The boundary line/handles stay at full opacity regardless,
  /// since they need to stay visible as UI chrome even when the shading
  /// itself is dialed down.
  final double overlayOpacity;

  @override
  State<GradientMaskOverlay> createState() => _GradientMaskOverlayState();
}

enum _Handle { linearStart, linearEnd, radialCenter, radialEdge }

const _hitRadius = 24.0;

class _GradientMaskOverlayState extends State<GradientMaskOverlay> {
  _Handle? _active;
  Offset _lastLocal = Offset.zero;

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

  Offset _toLocal(double nx, double ny, Rect r) =>
      Offset(r.left + nx * r.width, r.top + ny * r.height);

  Offset _toNormalized(Offset local, Rect r) =>
      Offset((local.dx - r.left) / r.width, (local.dy - r.top) / r.height);

  void _handlePanStart(DragStartDetails details, Rect imageRect) {
    _lastLocal = details.localPosition;
    final mask = widget.mask;
    if (mask.type == MaskType.linearGradient) {
      final start = _toLocal(mask.linear.startX, mask.linear.startY, imageRect);
      final end = _toLocal(mask.linear.endX, mask.linear.endY, imageRect);
      final dStart = (_lastLocal - start).distance;
      final dEnd = (_lastLocal - end).distance;
      final closest = dStart <= dEnd ? dStart : dEnd;
      _active = closest > _hitRadius
          ? null
          : (dStart <= dEnd ? _Handle.linearStart : _Handle.linearEnd);
    } else {
      final center = _toLocal(
        mask.radial.centerX,
        mask.radial.centerY,
        imageRect,
      );
      final radiusPx = mask.radial.radius * imageRect.width;
      final edge = center + Offset(radiusPx, 0);
      final dCenter = (_lastLocal - center).distance;
      final dEdge = (_lastLocal - edge).distance;
      final closest = dCenter <= dEdge ? dCenter : dEdge;
      _active = closest > _hitRadius
          ? null
          : (dCenter <= dEdge ? _Handle.radialCenter : _Handle.radialEdge);
    }
  }

  MaskLayer _applyDrag(Offset local, Rect imageRect) {
    final mask = widget.mask;
    switch (_active) {
      case _Handle.linearStart:
        final n = _toNormalized(local, imageRect);
        return mask.copyWith(
          linear: mask.linear.copyWith(startX: n.dx, startY: n.dy),
        );
      case _Handle.linearEnd:
        final n = _toNormalized(local, imageRect);
        return mask.copyWith(
          linear: mask.linear.copyWith(endX: n.dx, endY: n.dy),
        );
      case _Handle.radialCenter:
        final n = _toNormalized(local, imageRect);
        return mask.copyWith(
          radial: mask.radial.copyWith(centerX: n.dx, centerY: n.dy),
        );
      case _Handle.radialEdge:
        final center = _toLocal(
          mask.radial.centerX,
          mask.radial.centerY,
          imageRect,
        );
        final radius = (local - center).distance / imageRect.width;
        return mask.copyWith(radial: mask.radial.copyWith(radius: radius));
      case null:
        return mask;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, Rect imageRect) {
    if (_active == null) {
      return;
    }
    _lastLocal = details.localPosition;
    widget.onChanged(_applyDrag(_lastLocal, imageRect));
  }

  void _handlePanEnd(Rect imageRect) {
    if (_active == null) {
      return;
    }
    widget.onChangeEnd(_applyDrag(_lastLocal, imageRect));
    _active = null;
  }

  @override
  Widget build(BuildContext context) {
    final imageRect = _imageRect();
    final mask = widget.mask;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) => _handlePanStart(details, imageRect),
      onPanUpdate: (details) => _handlePanUpdate(details, imageRect),
      onPanEnd: (_) => _handlePanEnd(imageRect),
      child: widget.showOverlay
          ? CustomPaint(
              size: widget.containerSize,
              painter: mask.type == MaskType.linearGradient
                  ? _LinearHandlesPainter(
                      start: _toLocal(
                        mask.linear.startX,
                        mask.linear.startY,
                        imageRect,
                      ),
                      end: _toLocal(
                        mask.linear.endX,
                        mask.linear.endY,
                        imageRect,
                      ),
                      shadeAlpha: widget.overlayOpacity,
                    )
                  : _RadialHandlesPainter(
                      center: _toLocal(
                        mask.radial.centerX,
                        mask.radial.centerY,
                        imageRect,
                      ),
                      radiusPx: mask.radial.radius * imageRect.width,
                      innerRadiusPx:
                          mask.radial.radius *
                          (1.0 - mask.radial.feather.clamp(0.0, 1.0)) *
                          imageRect.width,
                      shadeAlpha: widget.overlayOpacity,
                    ),
            )
          : SizedBox.fromSize(size: widget.containerSize),
    );
  }
}

void _drawHandle(Canvas canvas, Offset center) {
  canvas.drawCircle(center, 7, Paint()..color = DarkmoonColors.accent);
  canvas.drawCircle(
    center,
    7,
    Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5,
  );
}

class _LinearHandlesPainter extends CustomPainter {
  const _LinearHandlesPainter({
    required this.start,
    required this.end,
    required this.shadeAlpha,
  });

  final Offset start;
  final Offset end;
  final double shadeAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    // Shades the actual coverage area — a real ui.Gradient.linear with
    // clamped tiling matches the mask's own alpha formula exactly (full
    // strength up to `start`, fading to zero by `end`, flat beyond both),
    // so what's shaded here is exactly what the render pipeline applies.
    final shaderPaint = Paint()
      ..shader = ui.Gradient.linear(start, end, [
        DarkmoonColors.accent.withValues(alpha: shadeAlpha),
        DarkmoonColors.accent.withValues(alpha: 0),
      ]);
    canvas.drawRect(Offset.zero & size, shaderPaint);

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = DarkmoonColors.accent
        ..strokeWidth = 1.5,
    );
    // Perpendicular ticks at each end mark exactly where full effect
    // starts and where it fades to nothing, since that's easy to lose
    // track of once the shaded band itself gets subtle near the edges.
    final direction = end - start;
    final length = direction.distance;
    if (length > 0) {
      final unit = direction / length;
      final perp = Offset(-unit.dy, unit.dx) * 24;
      canvas.drawLine(start - perp, start + perp, _tickPaint());
      canvas.drawLine(end - perp, end + perp, _tickPaint());
    }

    _drawHandle(canvas, start);
    _drawHandle(canvas, end);
  }

  @override
  bool shouldRepaint(covariant _LinearHandlesPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.shadeAlpha != shadeAlpha;
}

Paint _tickPaint() => Paint()
  ..color = DarkmoonColors.accent.withValues(alpha: 0.7)
  ..strokeWidth = 1;

class _RadialHandlesPainter extends CustomPainter {
  const _RadialHandlesPainter({
    required this.center,
    required this.radiusPx,
    required this.innerRadiusPx,
    required this.shadeAlpha,
  });

  final Offset center;
  final double radiusPx;
  final double innerRadiusPx;
  final double shadeAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    // Shades the covered area the same way the linear painter does — a
    // radial shader fading from the inner (full-strength) radius out to
    // the outer (zero-strength) radius, matching the mask's own feather.
    final shaderPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radiusPx <= 0 ? 0.001 : radiusPx,
        [
          DarkmoonColors.accent.withValues(alpha: shadeAlpha),
          DarkmoonColors.accent.withValues(alpha: shadeAlpha),
          DarkmoonColors.accent.withValues(alpha: 0),
        ],
        [
          0.0,
          radiusPx <= 0 ? 0.0 : (innerRadiusPx / radiusPx).clamp(0.0, 1.0),
          1.0,
        ],
      );
    canvas.drawRect(Offset.zero & size, shaderPaint);

    canvas.drawCircle(
      center,
      radiusPx,
      Paint()
        ..color = DarkmoonColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (innerRadiusPx > 0 && innerRadiusPx < radiusPx) {
      canvas.drawCircle(
        center,
        innerRadiusPx,
        Paint()
          ..color = DarkmoonColors.accent.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    _drawHandle(canvas, center);
    _drawHandle(canvas, center + Offset(radiusPx, 0));
  }

  @override
  bool shouldRepaint(covariant _RadialHandlesPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.radiusPx != radiusPx ||
      oldDelegate.innerRadiusPx != innerRadiusPx ||
      oldDelegate.shadeAlpha != shadeAlpha;
}
