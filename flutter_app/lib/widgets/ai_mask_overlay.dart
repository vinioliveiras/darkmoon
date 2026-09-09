import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../render/mask.dart';
import '../theme.dart';

/// The canvas layer for the four model-backed mask types.
///
/// Shades exactly the pixels the mask covers, from the same [AiMaskMap]
/// and the same [computeMaskAlpha] the render uses — so what is shaded
/// here is what the adjustments will land on, including the Depth band's
/// Near/Far/feather, which are otherwise impossible to aim.
///
/// For [MaskType.subject] it is also the input surface: dragging draws the
/// box handed to the model, and a tap is a point prompt. The other three
/// have nothing to aim, so they are display-only and let clicks through to
/// the canvas beneath.
class AiMaskOverlay extends StatefulWidget {
  const AiMaskOverlay({
    super.key,
    required this.containerSize,
    required this.imageWidth,
    required this.imageHeight,
    required this.mask,
    required this.onChanged,
    required this.onChangeEnd,
    this.map,
    this.showOverlay = true,
    this.overlayOpacity = 0.5,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;
  final MaskLayer mask;

  /// This mask's resolved model output, or null while it is still being
  /// computed (or failed) — in which case nothing is shaded, and a Subject
  /// box can still be drawn.
  final AiMaskMap? map;

  /// Emitted with the whole updated layer, matching the gradient and brush
  /// overlays: [onChanged] continuously while dragging, [onChangeEnd] once
  /// on release (which is what commits to history and, for Subject,
  /// triggers the model).
  final ValueChanged<MaskLayer> onChanged;
  final ValueChanged<MaskLayer> onChangeEnd;

  final bool showOverlay;
  final double overlayOpacity;

  @override
  State<AiMaskOverlay> createState() => _AiMaskOverlayState();
}

class _AiMaskOverlayState extends State<AiMaskOverlay> {
  ui.Image? _alphaImage;

  /// Guards against an out-of-order [ui.decodeImageFromPixels] callback
  /// replacing a newer overlay with an older one.
  int _requestId = 0;

  /// The in-progress drag, in normalized image coordinates — null when not
  /// dragging. Drawn directly rather than round-tripping through the mask,
  /// so the box tracks the cursor even though the model behind it only
  /// runs on release.
  Offset? _dragStart;
  Offset? _dragCurrent;

  @override
  void initState() {
    super.initState();
    _rebuildOverlay();
  }

  @override
  void didUpdateWidget(AiMaskOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compared field by field rather than by mask identity: the editor
    // rebuilds its mask list on every render tick, so an identity check
    // would recompute a full-frame alpha buffer and decode an image for
    // every drag of an unrelated slider.
    final old = oldWidget.mask;
    final now = widget.mask;
    if (oldWidget.map != widget.map ||
        oldWidget.overlayOpacity != widget.overlayOpacity ||
        old.inverted != now.inverted ||
        old.opacity != now.opacity ||
        old.depth.near != now.depth.near ||
        old.depth.far != now.depth.far ||
        old.depth.feather != now.depth.feather) {
      _rebuildOverlay();
    }
  }

  @override
  void dispose() {
    _alphaImage?.dispose();
    super.dispose();
  }

  void _rebuildOverlay() {
    final map = widget.map;
    if (map == null) {
      final old = _alphaImage;
      _alphaImage = null;
      old?.dispose();
      return;
    }
    final requestId = ++_requestId;
    // At the map's own resolution, not the canvas's: the alpha comes from
    // a map that is already this size, so computing it any larger would
    // only interpolate the same values into more pixels.
    final alpha = computeMaskAlpha(
      widget.mask,
      map.width,
      map.height,
      aiMap: map,
    );
    final pixels = Uint8List(map.width * map.height * 4);
    final accentR = DarkmoonColors.accent.r.round();
    final accentG = DarkmoonColors.accent.g.round();
    final accentB = DarkmoonColors.accent.b.round();
    for (var p = 0; p < alpha.length; p++) {
      final i = p * 4;
      pixels[i] = accentR;
      pixels[i + 1] = accentG;
      pixels[i + 2] = accentB;
      pixels[i + 3] = (alpha[p].clamp(0.0, 1.0) * 255 * widget.overlayOpacity)
          .round();
    }
    ui.decodeImageFromPixels(
      pixels,
      map.width,
      map.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted || requestId != _requestId) {
          image.dispose();
          return;
        }
        final old = _alphaImage;
        setState(() => _alphaImage = image);
        old?.dispose();
      },
    );
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

  Offset _normalize(Offset local) {
    final rect = _imageRect();
    return Offset(
      ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  MaskLayer _withDrag(Offset start, Offset end) => widget.mask.copyWith(
    subject: SubjectGeometry(
      startX: start.dx,
      startY: start.dy,
      endX: end.dx,
      endY: end.dy,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final image = widget.showOverlay ? _alphaImage : null;
    final dragStart = _dragStart;
    final dragCurrent = _dragCurrent;
    final painter = CustomPaint(
      size: widget.containerSize,
      painter: _AiMaskPainter(
        image: image,
        imageRect: _imageRect(),
        box: dragStart != null && dragCurrent != null
            ? Rect.fromPoints(dragStart, dragCurrent)
            : null,
      ),
    );
    if (widget.mask.type != MaskType.subject) {
      // Display only — an IgnorePointer rather than a transparent
      // GestureDetector so panning and zooming the canvas underneath keeps
      // working while a Sky or Depth mask is selected.
      return IgnorePointer(child: painter);
    }
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          // A degenerate box: SubjectGeometry reads start == end as a
          // point prompt, which is the faster gesture for one clear
          // object.
          final point = _normalize(details.localPosition);
          widget.onChangeEnd(_withDrag(point, point));
        },
        onPanStart: (details) {
          final point = _normalize(details.localPosition);
          setState(() {
            _dragStart = point;
            _dragCurrent = point;
          });
        },
        onPanUpdate: (details) {
          setState(() => _dragCurrent = _normalize(details.localPosition));
        },
        onPanEnd: (_) {
          final start = _dragStart;
          final end = _dragCurrent;
          setState(() {
            _dragStart = null;
            _dragCurrent = null;
          });
          if (start == null || end == null) {
            return;
          }
          widget.onChangeEnd(_withDrag(start, end));
        },
        child: painter,
      ),
    );
  }
}

/// Draws the shaded mask (a precomputed [image], since
/// [ui.decodeImageFromPixels] is async and [CustomPainter.paint] isn't)
/// and, while dragging, the Subject prompt box.
class _AiMaskPainter extends CustomPainter {
  const _AiMaskPainter({
    required this.image,
    required this.imageRect,
    this.box,
  });

  final ui.Image? image;
  final Rect imageRect;

  /// The in-progress drag, in normalized image coordinates.
  final Rect? box;

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        imageRect,
        Paint()..filterQuality = FilterQuality.low,
      );
    }
    final box = this.box;
    if (box == null) {
      return;
    }
    final rect = Rect.fromLTRB(
      imageRect.left + box.left * imageRect.width,
      imageRect.top + box.top * imageRect.height,
      imageRect.left + box.right * imageRect.width,
      imageRect.top + box.bottom * imageRect.height,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = DarkmoonColors.accent,
    );
  }

  @override
  bool shouldRepaint(_AiMaskPainter old) =>
      old.image != image || old.imageRect != imageRect || old.box != box;
}
