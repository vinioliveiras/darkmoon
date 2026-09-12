// Frame Image (2026-09-12): a border composed around the exported photo —
// Solstice's "Frame Image", which is its collage tool with one picture:
// a background colour, a gap around the picture, rounded corners and a
// choice of outer aspect ratio. Export-time only, on the CPU like the
// rest of the export: the frame is part of the file, not of the edit.
// Since 2026-09-13 it is the Albums right-click "Frame image" action
// (library/frame_image_dialog.dart) rather than an export-dialog
// section, saving `<name>_Framed` beside the original like Solstice.

import 'dart:math' as math;

import 'package:image/image.dart' as img;

/// The outer shape of the framed image — Solstice's ratio presets, each
/// in landscape; [FrameOptions.portrait] turns one on its side.
enum FrameAspect {
  /// The photo's own ratio plus the border on every side.
  original(null),
  square(1.0),
  ratio5x4(5 / 4),
  ratio4x3(4 / 3),
  ratio3x2(3 / 2),
  ratio16x9(16 / 9);

  const FrameAspect(this.ratio);

  /// width / height in landscape, null for [original].
  final double? ratio;

  /// The preset's label, `5:4` and so on; empty for [original].
  String get label => switch (this) {
    original => '',
    square => '1:1',
    ratio5x4 => '5:4',
    ratio4x3 => '4:3',
    ratio3x2 => '3:2',
    ratio16x9 => '16:9',
  };
}

class FrameOptions {
  const FrameOptions({
    this.paddingPercent = defaultPaddingPercent,
    this.radiusPercent = 0,
    this.background = 0xFFFFFFFF,
    this.aspect = FrameAspect.original,
    this.portrait = false,
  });

  /// The border, as a percentage of the photo's long edge (0..50). A
  /// print mat sits around 4-8%; the house rule's 50% Amount default does
  /// not apply here because half a photo of border is a thumbnail, not a
  /// stronger frame.
  static const defaultPaddingPercent = 6;

  final int paddingPercent;

  /// Corner radius of the photo, as a percentage of its short edge
  /// (0..50; 50 makes a circle of a square).
  final int radiusPercent;

  /// ARGB. The alpha is ignored — an export has no transparency.
  final int background;

  final FrameAspect aspect;

  /// [aspect] turned on its side (a 3:2 frame becomes 2:3). Ignored for
  /// [FrameAspect.original] and [FrameAspect.square].
  final bool portrait;

  /// width / height of the frame, null for the photo's own.
  double? get ratio {
    final r = aspect.ratio;
    return r == null || !portrait ? r : 1 / r;
  }

  FrameOptions copyWith({
    int? paddingPercent,
    int? radiusPercent,
    int? background,
    FrameAspect? aspect,
    bool? portrait,
  }) => FrameOptions(
    paddingPercent: paddingPercent ?? this.paddingPercent,
    radiusPercent: radiusPercent ?? this.radiusPercent,
    background: background ?? this.background,
    aspect: aspect ?? this.aspect,
    portrait: portrait ?? this.portrait,
  );
}

/// The framed image's size for a [width] x [height] photo — what the
/// dialog shows and what [applyFrame] produces.
({int width, int height, int padding}) frameSizeFor(
  int width,
  int height,
  FrameOptions options,
) {
  final padding = (math.max(width, height) * options.paddingPercent / 100)
      .round();
  var outW = width + 2 * padding;
  var outH = height + 2 * padding;
  final ratio = options.ratio;
  if (ratio != null) {
    // Grow whichever side is short of the ratio; never shrink, so the
    // border is at least the padding on every side.
    if (outW / outH < ratio) {
      outW = (outH * ratio).round();
    } else {
      outH = (outW / ratio).round();
    }
  }
  return (width: outW, height: outH, padding: padding);
}

/// [photo] centred on a [FrameOptions.background] canvas of
/// [frameSizeFor]'s size, its corners rounded by [FrameOptions.radiusPercent]
/// with a one-pixel anti-aliased edge. RGB out, like the export encodes.
img.Image applyFrame(img.Image photo, FrameOptions options) {
  final size = frameSizeFor(photo.width, photo.height, options);
  final bgR = (options.background >> 16) & 0xff;
  final bgG = (options.background >> 8) & 0xff;
  final bgB = options.background & 0xff;
  final out = img.Image(width: size.width, height: size.height, numChannels: 3);
  img.fill(out, color: img.ColorRgb8(bgR, bgG, bgB));
  final left = (size.width - photo.width) ~/ 2;
  final top = (size.height - photo.height) ~/ 2;
  final radius =
      math.min(photo.width, photo.height) * options.radiusPercent / 100;
  for (var y = 0; y < photo.height; y++) {
    for (var x = 0; x < photo.width; x++) {
      final coverage = radius <= 0
          ? 1.0
          : _cornerCoverage(
              x + 0.5,
              y + 0.5,
              photo.width,
              photo.height,
              radius,
            );
      if (coverage <= 0) continue;
      final px = photo.getPixel(x, y);
      final r = px.r.toDouble(), g = px.g.toDouble(), b = px.b.toDouble();
      out.setPixelRgb(
        left + x,
        top + y,
        (bgR + (r - bgR) * coverage).round(),
        (bgG + (g - bgG) * coverage).round(),
        (bgB + (b - bgB) * coverage).round(),
      );
    }
  }
  return out;
}

/// How much of the pixel centred at ([px], [py]) lies inside the rounded
/// rectangle of [w] x [h] with corner [radius]: 1 away from the corners,
/// a one-pixel ramp across the arc, 0 outside it.
double _cornerCoverage(double px, double py, int w, int h, double radius) {
  final cx = px < radius
      ? radius
      : px > w - radius
      ? w - radius
      : px;
  final cy = py < radius
      ? radius
      : py > h - radius
      ? h - radius
      : py;
  if (cx == px && cy == py) return 1.0;
  final d = math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  return (radius + 0.5 - d).clamp(0.0, 1.0);
}
