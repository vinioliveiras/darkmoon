import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../render/mask.dart';
import '../render/preview_pixels.dart';
import '../theme.dart';

/// Tap-to-sample surface for a Color Range mask — clicking anywhere on the
/// image picks that point's color as the mask's reference color. Also
/// shades exactly the pixels the mask currently covers, computed with the
/// same [computeMaskAlpha]/[ColorRangeGeometry] math the render pipeline
/// uses, so what's shaded here is exactly what the effect applies to — the
/// same "what you see is what's masked" idea as the gradient masks'
/// overlay, just per-pixel instead of a smooth gradient shape.
class ColorRangeOverlay extends StatefulWidget {
  const ColorRangeOverlay({
    super.key,
    required this.containerSize,
    required this.imageWidth,
    required this.imageHeight,
    required this.onSample,
    this.mask,
    this.previewImage,
    this.showOverlay = true,
    this.overlayOpacity = 0.5,
  });

  final Size containerSize;
  final int imageWidth;
  final int imageHeight;

  /// Normalized (0..1) image coordinates of the tapped point.
  final void Function(double nx, double ny) onSample;

  /// The mask being edited, and the currently-rendered preview (the very
  /// `ui.Image` the canvas is painting) to sample its color-distance alpha
  /// from — null while either isn't available yet, in which case no
  /// shading is drawn, only tap-to-sample still works.
  ///
  /// This used to be the preview's JPEG bytes, decoded here with
  /// `package:image`. The render pipeline no longer produces a preview
  /// JPEG at all (see `render_job.dart`'s `RenderResult.previewRgba`), and
  /// reading the pixels back off the image itself is both cheaper and
  /// exact — no lossy generation between what the canvas shows and what
  /// the color distance is measured against.
  final MaskLayer? mask;
  final ui.Image? previewImage;

  /// Whether the shaded selection overlay should be drawn — a toggle the
  /// user controls, same as the other mask overlays' visibility.
  final bool showOverlay;

  /// How opaque the shaded selection is, 0..1 — user-adjustable, same idea
  /// as the other mask overlays' opacity control.
  final double overlayOpacity;

  @override
  State<ColorRangeOverlay> createState() => _ColorRangeOverlayState();
}

class _ColorRangeOverlayState extends State<ColorRangeOverlay> {
  ui.Image? _alphaImage;
  int _requestId = 0;

  // Cached readback of [widget.previewImage] — a mask's tolerance/feather
  // sliders change (and so trigger a rebuild) far more often than the
  // preview itself re-renders, so pulling the pixels back off the GPU on
  // every slider tick would be wasteful; only [computeMaskAlpha] (cheap)
  // needs to rerun that often.
  ui.Image? _decodedForImage;
  Float32List? _decodedRgb;
  int _decodedWidth = 0;
  int _decodedHeight = 0;

  @override
  void initState() {
    super.initState();
    _scheduleRebuild();
  }

  @override
  void didUpdateWidget(covariant ColorRangeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showOverlay &&
        (!identical(widget.mask, oldWidget.mask) ||
            !identical(widget.previewImage, oldWidget.previewImage) ||
            widget.imageWidth != oldWidget.imageWidth ||
            widget.imageHeight != oldWidget.imageHeight ||
            widget.overlayOpacity != oldWidget.overlayOpacity)) {
      _scheduleRebuild();
    } else if (!widget.showOverlay && oldWidget.showOverlay) {
      setState(() => _alphaImage = null);
    }
  }

  @override
  void dispose() {
    _alphaImage?.dispose();
    super.dispose();
  }

  Future<void> _scheduleRebuild() async {
    final mask = widget.mask;
    final previewImage = widget.previewImage;
    if (!widget.showOverlay || mask == null || previewImage == null) {
      return;
    }
    if (!identical(_decodedForImage, previewImage)) {
      // Own a handle for the duration of the readback — the editor
      // disposes a preview the moment its replacement lands, and reading
      // a disposed image throws.
      final handle = previewImage.clone();
      final Float32List? rgb;
      try {
        rgb = await rgbFloatsFromImage(handle);
      } finally {
        handle.dispose();
      }
      // Another rebuild may have landed (and cached its own readback)
      // while this one was in flight, or the widget may be gone.
      if (rgb == null || !mounted || widget.previewImage != previewImage) {
        return;
      }
      _decodedForImage = previewImage;
      _decodedRgb = rgb;
      _decodedWidth = previewImage.width;
      _decodedHeight = previewImage.height;
    }
    final rgb = _decodedRgb;
    if (rgb == null) {
      return;
    }
    final requestId = ++_requestId;
    final width = _decodedWidth;
    final height = _decodedHeight;
    final alpha = computeMaskAlpha(
      mask,
      width,
      height,
      sourceForColorRange: rgb,
    );
    final pixels = Uint8List(width * height * 4);
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
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, (
      image,
    ) {
      if (!mounted || requestId != _requestId) {
        image.dispose();
        return;
      }
      final old = _alphaImage;
      setState(() => _alphaImage = image);
      old?.dispose();
    });
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
    final image = widget.showOverlay ? _alphaImage : null;
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
          widget.onSample(nx, ny);
        },
        child: image == null
            ? null
            : CustomPaint(
                size: widget.containerSize,
                painter: _ColorRangeAlphaPainter(
                  image: image,
                  imageRect: _imageRect(),
                ),
              ),
      ),
    );
  }
}

/// Draws a precomputed alpha [image] (built by [_ColorRangeOverlayState],
/// since [ui.decodeImageFromPixels] is async and [CustomPainter.paint]
/// isn't) scaled up to fit [imageRect] — cheaper than recomputing at every
/// zoom level, and the alpha field is smooth enough that upscaling doesn't
/// visibly matter.
class _ColorRangeAlphaPainter extends CustomPainter {
  const _ColorRangeAlphaPainter({required this.image, required this.imageRect});

  final ui.Image image;
  final Rect imageRect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      imageRect,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _ColorRangeAlphaPainter oldDelegate) =>
      !identical(oldDelegate.image, image) ||
      oldDelegate.imageRect != imageRect;
}
