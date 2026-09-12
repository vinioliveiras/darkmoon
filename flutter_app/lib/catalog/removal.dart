import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;

/// One object removal (2026-09-12): where it was, as a coverage map, and
/// whether it is applied. What the "patches" of Solstice's inpainting
/// panel are here.
///
/// The coverage is kept as pixels rather than as the brush or mask it
/// came from, so a removal painted, one taken from a Subject mask and one
/// from a colour range are all the same thing afterwards — and can be
/// recomputed in a worker that has no model output or preview to
/// rasterise a mask from. Stored as a grayscale PNG, capped at
/// [removalMaxDimension] on the longer side: a few kilobytes in the
/// catalog for a brush, tens for a segmentation edge.
/// How a [Removal]'s hole is filled — see `edit_source_inpaint.dart`.
enum RemovalMode {
  /// The LaMa model paints what its surroundings suggest.
  ai,

  /// Pixels copied from [Removal.sourceDx]/[Removal.sourceDy] away.
  clone,

  /// Copied like [clone], then blended into the hole's own lighting.
  heal,

  /// A patch a generative server painted for a prompt, stored in
  /// [Removal.patchPng] and composited back — no model runs locally.
  generative,
}

class Removal {
  const Removal({
    required this.name,
    required this.width,
    required this.height,
    required this.alphaPng,
    this.visible = true,
    this.mode = RemovalMode.ai,
    this.sourceDx = 0,
    this.sourceDy = 0,
    this.patchPng,
    this.patchLeft = 0,
    this.patchTop = 0,
    this.patchWidth = 0,
    this.patchHeight = 0,
  });

  final RemovalMode mode;

  /// Clone/Heal: where the source sits relative to the hole, as a
  /// fraction of the frame's width and height (so it survives every
  /// resolution the removal is applied at).
  final double sourceDx;
  final double sourceDy;

  /// Generative: the server's patch as a PNG, and where it goes on the
  /// frame as fractions of its width and height.
  final Uint8List? patchPng;
  final double patchLeft;
  final double patchTop;
  final double patchWidth;
  final double patchHeight;

  final String name;
  final int width;
  final int height;

  /// Grayscale PNG, [width] by [height]: 255 where the removal is.
  final Uint8List alphaPng;

  /// Off, the removal is skipped, like a hidden patch.
  final bool visible;

  Removal copyWith({String? name, bool? visible}) => Removal(
    name: name ?? this.name,
    width: width,
    height: height,
    alphaPng: alphaPng,
    visible: visible ?? this.visible,
    mode: mode,
    sourceDx: sourceDx,
    sourceDy: sourceDy,
    patchPng: patchPng,
    patchLeft: patchLeft,
    patchTop: patchTop,
    patchWidth: patchWidth,
    patchHeight: patchHeight,
  );

  /// Tells this coverage from any other, for the result cache's key.
  /// Identifies the result, so the cache key changes when anything that
  /// changes the fill does: the coverage, the fill mode, the source
  /// offset, the generative patch.
  String get signature {
    final extra = switch (mode) {
      RemovalMode.ai => '',
      RemovalMode.clone || RemovalMode.heal =>
        '|${mode.name}|${sourceDx.toStringAsFixed(5)}|'
            '${sourceDy.toStringAsFixed(5)}',
      RemovalMode.generative =>
        '|generative|${patchPng == null ? '' : sha1.convert(patchPng!)}|'
            '$patchLeft|$patchTop|$patchWidth|$patchHeight',
    };
    return '${sha1.convert(alphaPng)}$extra';
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'visible': visible,
    'width': width,
    'height': height,
    'alpha': base64Encode(alphaPng),
    if (mode != RemovalMode.ai) 'mode': mode.name,
    if (mode == RemovalMode.clone || mode == RemovalMode.heal) ...{
      'sourceDx': sourceDx,
      'sourceDy': sourceDy,
    },
    if (mode == RemovalMode.generative && patchPng != null) ...{
      'patch': base64Encode(patchPng!),
      'patchLeft': patchLeft,
      'patchTop': patchTop,
      'patchWidth': patchWidth,
      'patchHeight': patchHeight,
    },
  };

  /// Null for anything that is not a removal record (an older format,
  /// a truncated entry).
  static Removal? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final width = raw['width'];
    final height = raw['height'];
    final alpha = raw['alpha'];
    if (width is! int || height is! int || alpha is! String) {
      return null;
    }
    try {
      final modeName = raw['mode'] as String?;
      final patch = raw['patch'] as String?;
      return Removal(
        name: raw['name'] as String? ?? '',
        visible: raw['visible'] as bool? ?? true,
        width: width,
        height: height,
        alphaPng: base64Decode(alpha),
        mode: modeName == null
            ? RemovalMode.ai
            : RemovalMode.values.firstWhere(
                (m) => m.name == modeName,
                orElse: () => RemovalMode.ai,
              ),
        sourceDx: (raw['sourceDx'] as num?)?.toDouble() ?? 0,
        sourceDy: (raw['sourceDy'] as num?)?.toDouble() ?? 0,
        patchPng: patch == null ? null : base64Decode(patch),
        patchLeft: (raw['patchLeft'] as num?)?.toDouble() ?? 0,
        patchTop: (raw['patchTop'] as num?)?.toDouble() ?? 0,
        patchWidth: (raw['patchWidth'] as num?)?.toDouble() ?? 0,
        patchHeight: (raw['patchHeight'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The longer side a removal's coverage is stored at.
const removalMaxDimension = 1536;

/// [alpha] (0..1, row-major) as a grayscale PNG.
Uint8List encodeAlphaPng(Float32List alpha, int width, int height) {
  final bytes = Uint8List(width * height);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = (alpha[i] * 255).round().clamp(0, 255);
  }
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: bytes.buffer,
    numChannels: 1,
  );
  return Uint8List.fromList(img.encodePng(image));
}

/// The coverage back from [encodeAlphaPng]'s PNG; null for a corrupt one.
({Float32List alpha, int width, int height})? decodeAlphaPng(Uint8List png) {
  final decoded = img.decodePng(png);
  if (decoded == null) {
    return null;
  }
  final width = decoded.width;
  final height = decoded.height;
  final alpha = Float32List(width * height);
  final gray = decoded.numChannels == 1
      ? decoded
      : decoded.convert(numChannels: 1);
  final bytes = gray.getBytes();
  if (bytes.length == width * height) {
    for (var i = 0; i < bytes.length; i++) {
      alpha[i] = bytes[i] / 255.0;
    }
  } else {
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        alpha[y * width + x] = gray.getPixel(x, y).r / 255.0;
      }
    }
  }
  return (alpha: alpha, width: width, height: height);
}

/// Grows the coverage by [radius] pixels in every direction — a square
/// maximum filter, run as two passes. Solstice's "Grow": a segmentation
/// mask stops exactly at the object's edge, and a fill that stops there
/// too leaves a halo of the object behind.
Float32List dilateAlpha(Float32List alpha, int width, int height, int radius) {
  if (radius <= 0) {
    return alpha;
  }
  final rows = Float32List(alpha.length);
  for (var y = 0; y < height; y++) {
    final row = y * width;
    for (var x = 0; x < width; x++) {
      var m = 0.0;
      final x0 = x - radius < 0 ? 0 : x - radius;
      final x1 = x + radius >= width ? width - 1 : x + radius;
      for (var i = x0; i <= x1; i++) {
        final v = alpha[row + i];
        if (v > m) m = v;
      }
      rows[row + x] = m;
    }
  }
  final out = Float32List(alpha.length);
  for (var x = 0; x < width; x++) {
    for (var y = 0; y < height; y++) {
      var m = 0.0;
      final y0 = y - radius < 0 ? 0 : y - radius;
      final y1 = y + radius >= height ? height - 1 : y + radius;
      for (var j = y0; j <= y1; j++) {
        final v = rows[j * width + x];
        if (v > m) m = v;
      }
      out[y * width + x] = m;
    }
  }
  return out;
}

/// [alpha] resampled from [width] by [height] to [newWidth] by
/// [newHeight] — a box average going down, bilinear going up.
Float32List resampleAlpha(
  Float32List alpha,
  int width,
  int height,
  int newWidth,
  int newHeight,
) {
  if (newWidth == width && newHeight == height) {
    return alpha;
  }
  final out = Float32List(newWidth * newHeight);
  if (newWidth < width || newHeight < height) {
    for (var y = 0; y < newHeight; y++) {
      final sy0 = (y * height / newHeight).floor();
      final sy1 = (((y + 1) * height / newHeight).ceil()).clamp(
        sy0 + 1,
        height,
      );
      for (var x = 0; x < newWidth; x++) {
        final sx0 = (x * width / newWidth).floor();
        final sx1 = (((x + 1) * width / newWidth).ceil()).clamp(sx0 + 1, width);
        var sum = 0.0;
        for (var sy = sy0; sy < sy1; sy++) {
          for (var sx = sx0; sx < sx1; sx++) {
            sum += alpha[sy * width + sx];
          }
        }
        out[y * newWidth + x] = sum / ((sy1 - sy0) * (sx1 - sx0));
      }
    }
    return out;
  }
  for (var y = 0; y < newHeight; y++) {
    final sy = ((y + 0.5) * height / newHeight - 0.5).clamp(0.0, height - 1.0);
    final y0 = sy.floor();
    final y1 = (y0 + 1).clamp(0, height - 1);
    final fy = sy - y0;
    for (var x = 0; x < newWidth; x++) {
      final sx = ((x + 0.5) * width / newWidth - 0.5).clamp(0.0, width - 1.0);
      final x0 = sx.floor();
      final x1 = (x0 + 1).clamp(0, width - 1);
      final fx = sx - x0;
      final a = alpha[y0 * width + x0] * (1 - fx) + alpha[y0 * width + x1] * fx;
      final b = alpha[y1 * width + x0] * (1 - fx) + alpha[y1 * width + x1] * fx;
      out[y * newWidth + x] = a * (1 - fy) + b * fy;
    }
  }
  return out;
}
