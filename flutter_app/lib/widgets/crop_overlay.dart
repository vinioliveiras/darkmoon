import 'dart:math' as math;

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

enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight, move, rotate }

const _handleHitRadius = 20.0;

/// How far outside the crop rect's top-right corner the rotate anchor sits
/// — along the same diagonal the corner itself sits on relative to the
/// crop's centre, so it reads as "an extension of that corner" rather
/// than a floating, disconnected dot.
const _rotateHandleOffset = 26.0;

/// Where the rotate anchor sits for a given [cropRect] — shared between
/// hit-testing ([_CropOverlayState._handlePanStart]) and painting
/// ([_CropPainter]) so the two can never drift apart.
Offset _rotateHandlePosition(Rect cropRect) {
  final center = cropRect.center;
  final corner = cropRect.topRight;
  final dir = (corner - center);
  final len = dir.distance;
  if (len < 1e-6) {
    return corner;
  }
  return corner + dir / len * _rotateHandleOffset;
}

/// Draggable crop rectangle, shown over the (already straightened/
/// keystoned) preview image while the Crop tool is active — same
/// `BoxFit.contain` letterbox math as the mask overlays, applied to
/// [params]'s crop rect instead of a mask's geometry.
///
/// [lockedAspectRatio], if set, constrains every drag to keep that
/// width/height ratio (Meridian's aspect-ratio-picker behavior);
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
    required this.straighteningActive,
    this.lockedAspectRatio,
    this.guidedModeActive = false,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;
  final CropTransformParams params;
  final ValueChanged<CropTransformParams> onChanged;
  final ValueChanged<CropTransformParams> onChangeEnd;
  final double? lockedAspectRatio;

  /// True while the Straighten slider is being actively dragged — shows a
  /// denser guide grid (instead of the default rule-of-thirds) so it's
  /// easier to see whether a horizon/vertical has been leveled.
  final bool straighteningActive;

  /// True while the "Guided" upright tool (PENDING.md item 27) is active —
  /// a drag no longer touches the crop rect at all; it draws one reference
  /// line the user is claiming should be perfectly horizontal or vertical
  /// (whichever it's closer to), and releasing computes the
  /// [CropTransformParams.straightenAngle] that levels it. Scoped to a
  /// single line for v1 (2026-09-02) — PENDING.md's own Auto/Level/
  /// Vertical/Full modes (real line-detection computer vision) and a
  /// multi-line keystone solve are explicitly deferred, not attempted here.
  final bool guidedModeActive;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  _CropHandle? _active;
  Offset _dragStartLocal = Offset.zero;
  CropTransformParams _dragStartParams = const CropTransformParams();

  /// Angle (radians, from the crop rect's centre to the drag start point)
  /// captured when a [_CropHandle.rotate] drag begins — every subsequent
  /// [_applyDrag] call measures the *change* in that angle, not the
  /// absolute one, so the anchor doesn't jump the moment the drag starts.
  double _rotateStartAngle = 0;

  /// The reference line currently being drawn in [CropOverlay.guidedModeActive]
  /// — null outside a guided drag. Local-pixel coordinates, same space as
  /// every other drag handler here.
  Offset? _guideStart;
  Offset? _guideEnd;

  /// Below this drag distance (px), a guided-mode release is treated as an
  /// accidental tap, not a real reference line — avoids a stray click
  /// producing a wild correction from a near-zero-length line (its angle
  /// is numerically unstable as length -> 0).
  static const _guideMinLengthPx = 12.0;

  /// The [CropTransformParams.straightenAngle] delta that would make the
  /// line from [start] to [end] perfectly horizontal or vertical —
  /// whichever it's already closer to. Returns 0 if the line is too short
  /// to trust (see [_guideMinLengthPx]).
  ///
  /// Math: a line's angle and its angle+180° describe the same line (no
  /// inherent direction), so first fold the raw atan2 into (-90, 90] —
  /// that's the deviation from horizontal. If that deviation is more than
  /// 45° (i.e. the line reads as closer to vertical), re-express it as the
  /// deviation from vertical instead. Either way, rotating the image by
  /// the NEGATIVE of that deviation levels the line — [rotatePoint] (see
  /// `render/geometry.dart`) rotates by a positive angle *clockwise* in
  /// this image's Y-down pixel space, and `crop_transform.dart`'s
  /// `applyCropAndTransform` derives the displayed (straightened) image as
  /// the source rotated by `+straightenAngle`, so a line tilted clockwise
  /// (positive deviation) needs a negative straightenAngle delta to cancel.
  double _guidedCorrectionDeg(Offset start, Offset end) {
    final delta = end - start;
    if (delta.distance < _guideMinLengthPx) {
      return 0;
    }
    var deviation = math.atan2(delta.dy, delta.dx) * 180.0 / math.pi;
    while (deviation > 90) {
      deviation -= 180;
    }
    while (deviation <= -90) {
      deviation += 180;
    }
    if (deviation.abs() > 45) {
      deviation = deviation > 0 ? deviation - 90 : deviation + 90;
    }
    return -deviation;
  }

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
    if (widget.guidedModeActive) {
      setState(() {
        _guideStart = details.localPosition;
        _guideEnd = details.localPosition;
      });
      return;
    }
    final cropRect = _cropRectLocal(imageRect);
    // Checked before the corners: the rotate anchor sits just outside the
    // top-right one (see _rotateHandlePosition's doc), so it needs first
    // pick within its own hit radius or a click meant for it would keep
    // resolving to the nearby corner instead.
    if ((_rotateHandlePosition(cropRect) - _dragStartLocal).distance <=
        _handleHitRadius) {
      _active = _CropHandle.rotate;
      final center = cropRect.center;
      _rotateStartAngle = math.atan2(
        _dragStartLocal.dy - center.dy,
        _dragStartLocal.dx - center.dx,
      );
      return;
    }
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
      case _CropHandle.rotate:
        final cropRect = Rect.fromLTRB(
          imageRect.left + start.cropLeft * imageRect.width,
          imageRect.top + start.cropTop * imageRect.height,
          imageRect.left + start.cropRight * imageRect.width,
          imageRect.top + start.cropBottom * imageRect.height,
        );
        final center = cropRect.center;
        final angle = math.atan2(local.dy - center.dy, local.dx - center.dx);
        final deltaDeg = (angle - _rotateStartAngle) * 180.0 / math.pi;
        final next = (start.straightenAngle + deltaDeg).clamp(-45.0, 45.0);
        return start.copyWith(straightenAngle: next);
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
    if (widget.guidedModeActive) {
      if (_guideStart == null) {
        return;
      }
      setState(() => _guideEnd = details.localPosition);
      final delta = _guidedCorrectionDeg(_guideStart!, details.localPosition);
      final next = (_dragStartParams.straightenAngle + delta).clamp(
        -45.0,
        45.0,
      );
      widget.onChanged(_dragStartParams.copyWith(straightenAngle: next));
      return;
    }
    if (_active == null) {
      return;
    }
    widget.onChanged(_applyDrag(details.localPosition, imageRect));
  }

  void _handlePanEnd() {
    if (widget.guidedModeActive) {
      final start = _guideStart;
      final end = _guideEnd;
      setState(() {
        _guideStart = null;
        _guideEnd = null;
      });
      if (start == null || end == null) {
        return;
      }
      final delta = _guidedCorrectionDeg(start, end);
      final next = (_dragStartParams.straightenAngle + delta).clamp(
        -45.0,
        45.0,
      );
      widget.onChangeEnd(_dragStartParams.copyWith(straightenAngle: next));
      return;
    }
    if (_active == null) {
      return;
    }
    // widget.params already holds the last-dragged rect — every
    // onPanUpdate already pushed it up via widget.onChanged. Re-deriving
    // it here from _dragStartLocal (the position the drag *started* at)
    // was the bug: dx/dy against itself is always zero, so this used to
    // commit the pre-drag rect right as the user released the mouse,
    // snapping the crop back to where it started.
    widget.onChangeEnd(widget.params);
    _active = null;
  }

  @override
  Widget build(BuildContext context) {
    final imageRect = _imageRect();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) => _handlePanStart(details, imageRect),
      onPanUpdate: (details) => _handlePanUpdate(details, imageRect),
      onPanEnd: (_) => _handlePanEnd(),
      child: CustomPaint(
        size: widget.containerSize,
        painter: _CropPainter(
          imageRect: imageRect,
          cropRect: _cropRectLocal(imageRect),
          denseGrid:
              widget.straighteningActive ||
              _active == _CropHandle.rotate ||
              widget.guidedModeActive,
          guideStart: _guideStart,
          guideEnd: _guideEnd,
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({
    required this.imageRect,
    required this.cropRect,
    required this.denseGrid,
    this.guideStart,
    this.guideEnd,
  });

  final Rect imageRect;
  final Rect cropRect;

  /// The "Guided" reference line currently being drawn — both null outside
  /// a guided drag. See [CropOverlay.guidedModeActive].
  final Offset? guideStart;
  final Offset? guideEnd;

  /// True while Straighten is being dragged — swaps the default 3x3
  /// rule-of-thirds grid for a denser one (easier to spot a tilted
  /// horizon/vertical against), at higher opacity so it reads clearly
  /// over the image during that specific interaction.
  final bool denseGrid;

  @override
  void paint(Canvas canvas, Size size) {
    // Darkens the discarded part of the IMAGE outside the crop rect — the
    // standard crop-tool convention. Scoped to imageRect, not the whole
    // canvas: with no crop yet applied cropRect == imageRect, and shading
    // the full container would additionally darken the letterbox bars
    // outside the image itself (already just the plain canvas background,
    // nothing to "discard" there), turning them visibly near-black the
    // instant the Crop tool is opened.
    final scrimPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final imagePath = Path()..addRect(imageRect);
    final cropPath = Path()..addRect(cropRect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, imagePath, cropPath),
      scrimPaint,
    );

    // Rule-of-thirds guide lines inside the crop rect — a denser grid
    // (item 28) while Straighten is actively being dragged, so a tilted
    // horizon/vertical is easier to line up against.
    final divisions = denseGrid ? 8 : 3;
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: denseGrid ? 0.7 : 0.5)
      ..strokeWidth = 1;
    for (var i = 1; i < divisions; i++) {
      final x = cropRect.left + cropRect.width * i / divisions;
      canvas.drawLine(
        Offset(x, cropRect.top),
        Offset(x, cropRect.bottom),
        gridPaint,
      );
      final y = cropRect.top + cropRect.height * i / divisions;
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

    // Handle drawn slightly inset from the true corner when that corner
    // sits at (or very near) the canvas's own edge — real bug fixed
    // 2026-09-01: an uncropped/full-frame crop rect puts corners exactly
    // on the canvas boundary, so the handle circle's outer edge got cut
    // off by whatever clips this canvas (the viewer panel's own bounds).
    // Only the *drawn* position moves; hit-testing below still uses the
    // real corner (cropRect.topLeft etc.) via [_handleHitRadius]'s
    // generous 20px radius, so dragging still feels anchored to the
    // actual corner, not the nudged dot.
    const handleRadius = 6.0;
    const edgePadding = handleRadius + 2;
    Offset inset(Offset corner) => Offset(
      corner.dx.clamp(edgePadding, size.width - edgePadding),
      corner.dy.clamp(edgePadding, size.height - edgePadding),
    );
    for (final corner in [
      cropRect.topLeft,
      cropRect.topRight,
      cropRect.bottomLeft,
      cropRect.bottomRight,
    ]) {
      final drawAt = inset(corner);
      canvas.drawCircle(
        drawAt,
        handleRadius,
        Paint()..color = DarkmoonColors.accent,
      );
      canvas.drawCircle(
        drawAt,
        handleRadius,
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Rotate anchor — a hollow ring (vs. the corners' filled dots) just
    // outside the top-right corner, connected to it by a short line so it
    // reads as "an extension of that corner" rather than a stray dot. See
    // _rotateHandlePosition's doc for the exact placement.
    final rotateAt = inset(_rotateHandlePosition(cropRect));
    canvas.drawLine(
      inset(cropRect.topRight),
      rotateAt,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      rotateAt,
      handleRadius,
      Paint()..color = Colors.black54,
    );
    canvas.drawCircle(
      rotateAt,
      handleRadius,
      Paint()
        ..color = DarkmoonColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // "Guided" reference line — a bright yellow so it reads clearly against
    // both the image and the white crop/grid lines above, with a small
    // filled dot at each end (no rotate-anchor-style ring, this isn't a
    // draggable handle once drawn).
    final gStart = guideStart;
    final gEnd = guideEnd;
    if (gStart != null && gEnd != null) {
      final guidePaint = Paint()
        ..color = const Color(0xFFFFD54A)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(gStart, gEnd, guidePaint);
      for (final p in [gStart, gEnd]) {
        canvas.drawCircle(p, 4.0, guidePaint..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.imageRect != imageRect ||
      oldDelegate.cropRect != cropRect ||
      oldDelegate.denseGrid != denseGrid ||
      oldDelegate.guideStart != guideStart ||
      oldDelegate.guideEnd != guideEnd;
}
