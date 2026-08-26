import 'dart:math' as math;
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

enum _Handle {
  linearStart,
  linearEnd,
  radialCenter,
  // One pair of opposite rim handles per ellipse axis; dragging either
  // side resizes that axis symmetrically around the center.
  radialRadiusX,
  radialRadiusY,
  // The detached knob past the ellipse's top rim that spins the shape.
  radialRotate,
}

const _hitRadius = 24.0;

/// Distance from the ellipse's top rim to the rotation knob, in px —
/// far enough out that it doesn't collide with the top axis handle.
const _rotateHandleGap = 26.0;

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
      final radial = mask.radial;
      final center = _toLocal(radial.centerX, radial.centerY, imageRect);
      final rxPx = radial.radius * imageRect.width;
      final ryPx = radial.effectiveRadiusY * imageRect.width;
      // The ellipse's own axes in screen space, rotated by its angle.
      final axisX = Offset(math.cos(radial.angle), math.sin(radial.angle));
      final axisY = Offset(-axisX.dy, axisX.dx);
      final candidates = <(_Handle, Offset)>[
        (_Handle.radialCenter, center),
        (_Handle.radialRadiusX, center + axisX * rxPx),
        (_Handle.radialRadiusX, center - axisX * rxPx),
        (_Handle.radialRadiusY, center + axisY * ryPx),
        (_Handle.radialRadiusY, center - axisY * ryPx),
        (_Handle.radialRotate, center - axisY * (ryPx + _rotateHandleGap)),
      ];
      _Handle? best;
      var bestDist = double.infinity;
      for (final (handle, pos) in candidates) {
        final d = (_lastLocal - pos).distance;
        if (d < bestDist) {
          bestDist = d;
          best = handle;
        }
      }
      _active = bestDist > _hitRadius ? null : best;
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
      case _Handle.radialRadiusX:
        final radial = mask.radial;
        final center = _toLocal(radial.centerX, radial.centerY, imageRect);
        final d = local - center;
        // Project the drag onto the ellipse's own X axis; |projection| so
        // both rim handles of the pair behave identically.
        final u =
            (d.dx * math.cos(radial.angle) + d.dy * math.sin(radial.angle))
                .abs();
        // Materialize radiusY at its current value so stretching one axis
        // no longer drags the other along via the circle fallback.
        return mask.copyWith(
          radial: radial.copyWith(
            radius: u / imageRect.width,
            radiusY: radial.effectiveRadiusY,
          ),
        );
      case _Handle.radialRadiusY:
        final radial = mask.radial;
        final center = _toLocal(radial.centerX, radial.centerY, imageRect);
        final d = local - center;
        final v =
            (d.dy * math.cos(radial.angle) - d.dx * math.sin(radial.angle))
                .abs();
        return mask.copyWith(
          radial: radial.copyWith(radiusY: v / imageRect.width),
        );
      case _Handle.radialRotate:
        final radial = mask.radial;
        final center = _toLocal(radial.centerX, radial.centerY, imageRect);
        final d = local - center;
        // The knob rides the ellipse's own "up" direction; the angle that
        // points that direction at the drag position is atan2 of the
        // swapped, y-negated delta (screen y grows downward).
        return mask.copyWith(
          radial: radial.copyWith(angle: math.atan2(d.dx, -d.dy)),
        );
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
                      radiusXPx: mask.radial.radius * imageRect.width,
                      radiusYPx:
                          mask.radial.effectiveRadiusY * imageRect.width,
                      angle: mask.radial.angle,
                      innerFraction:
                          1.0 - mask.radial.feather.clamp(0.0, 1.0),
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
    required this.radiusXPx,
    required this.radiusYPx,
    required this.angle,
    required this.innerFraction,
    required this.shadeAlpha,
  });

  final Offset center;
  final double radiusXPx;
  final double radiusYPx;

  /// Rotation of the ellipse, radians, clockwise on screen.
  final double angle;

  /// Where the full-strength region ends, as a fraction (0..1) of the
  /// ellipse — `1 - feather`, mirroring the mask's own falloff.
  final double innerFraction;
  final double shadeAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    final rx = radiusXPx <= 0 ? 0.001 : radiusXPx;
    final ry = radiusYPx <= 0 ? 0.001 : radiusYPx;

    // Shades the covered area the same way the linear painter does. The
    // shader is a *unit* radial gradient stretched into the rotated
    // ellipse by a matrix, so its falloff matches the mask's normalized
    // elliptical distance exactly.
    final m = Matrix4.identity()
      ..translateByDouble(center.dx, center.dy, 0, 1)
      ..rotateZ(angle)
      ..scaleByDouble(rx, ry, 1, 1);
    final shaderPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        1.0,
        [
          DarkmoonColors.accent.withValues(alpha: shadeAlpha),
          DarkmoonColors.accent.withValues(alpha: shadeAlpha),
          DarkmoonColors.accent.withValues(alpha: 0),
        ],
        [0.0, innerFraction.clamp(0.0, 1.0), 1.0],
        TileMode.clamp,
        m.storage,
      );
    canvas.drawRect(Offset.zero & size, shaderPaint);

    // Boundary, feather boundary and the rotation-knob stem are all drawn
    // in the ellipse's own rotated frame.
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
      Paint()
        ..color = DarkmoonColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    if (innerFraction > 0 && innerFraction < 1) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: rx * 2 * innerFraction,
          height: ry * 2 * innerFraction,
        ),
        Paint()
          ..color = DarkmoonColors.accent.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.drawLine(
      Offset(0, -ry),
      Offset(0, -(ry + _rotateHandleGap)),
      Paint()
        ..color = DarkmoonColors.accent.withValues(alpha: 0.7)
        ..strokeWidth = 1,
    );
    canvas.restore();

    // Handles sit at the rotated axis endpoints; drawn unrotated so the
    // dots stay crisp circles.
    final axisX = Offset(math.cos(angle), math.sin(angle));
    final axisY = Offset(-axisX.dy, axisX.dx);
    _drawHandle(canvas, center);
    _drawHandle(canvas, center + axisX * rx);
    _drawHandle(canvas, center - axisX * rx);
    _drawHandle(canvas, center + axisY * ry);
    _drawHandle(canvas, center - axisY * ry);
    _drawRotateHandle(canvas, center - axisY * (ry + _rotateHandleGap));
  }

  @override
  bool shouldRepaint(covariant _RadialHandlesPainter oldDelegate) =>
      oldDelegate.center != center ||
      oldDelegate.radiusXPx != radiusXPx ||
      oldDelegate.radiusYPx != radiusYPx ||
      oldDelegate.angle != angle ||
      oldDelegate.innerFraction != innerFraction ||
      oldDelegate.shadeAlpha != shadeAlpha;
}

/// The rotation knob: hollow ring, visually distinct from the filled
/// resize/move dots so it reads as "spin", not "stretch".
void _drawRotateHandle(Canvas canvas, Offset center) {
  canvas.drawCircle(center, 6, Paint()..color = Colors.black54);
  canvas.drawCircle(
    center,
    6,
    Paint()
      ..color = DarkmoonColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
}
