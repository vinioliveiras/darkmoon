import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../render/mask.dart';
import '../theme.dart';

/// The canvas layer for the model-backed mask types.
///
/// Shades exactly the pixels the mask covers, from the same [AiMaskMap]
/// and the same [computeMaskAlpha] the render uses — so what is shaded
/// here is what the adjustments will land on, including the Depth band's
/// Near/Far/feather, which are otherwise impossible to aim.
///
/// Display only, and deliberately: none of these three types takes any
/// input from the canvas. (The removed Subject type did — a box dragged
/// over the photo — which is why this was once a gesture surface.)
class AiMaskOverlay extends StatefulWidget {
  const AiMaskOverlay({
    super.key,
    required this.containerSize,
    required this.imageWidth,
    required this.imageHeight,
    required this.mask,
    this.map,
    this.showOverlay = true,
    this.overlayOpacity = 0.5,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;
  final MaskLayer mask;

  /// This mask's resolved model output, or null while it is still being
  /// computed (or failed) — in which case nothing is shaded.
  final AiMaskMap? map;

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

  @override
  Widget build(BuildContext context) {
    // IgnorePointer rather than a transparent GestureDetector: panning and
    // zooming the canvas underneath has to keep working while one of these
    // masks is selected.
    return IgnorePointer(
      child: CustomPaint(
        size: widget.containerSize,
        painter: _AiMaskPainter(
          image: widget.showOverlay ? _alphaImage : null,
          imageRect: _imageRect(),
        ),
      ),
    );
  }
}

/// Draws the shaded mask — precomputed by [_AiMaskOverlayState], since
/// [ui.decodeImageFromPixels] is async and [CustomPainter.paint] isn't.
class _AiMaskPainter extends CustomPainter {
  const _AiMaskPainter({required this.image, required this.imageRect});

  final ui.Image? image;
  final Rect imageRect;

  @override
  void paint(Canvas canvas, Size size) {
    final image = this.image;
    if (image == null) {
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_AiMaskPainter old) =>
      old.image != image || old.imageRect != imageRect;
}
