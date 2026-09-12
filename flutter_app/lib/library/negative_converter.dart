// The Albums "Convert negative" action's workers (2026-09-12) — every
// function here is a plain top-level one so `compute` can run it off the
// UI thread: the dialog's preview (a cached preview JPEG, shrunk, with
// its density bounds measured once and the conversion re-run per slider
// move) and the real conversion of a file, which decodes the source at
// full resolution, converts it and writes a 16-bit `<name>_Positive.tiff`
// beside it — Solstice's output, so the positive is a normal file the
// editor opens like any other.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../native/common_image.dart';
import '../render/negative.dart';

/// The dialog's preview source: the photo shrunk to [width] x [height]
/// and the density bounds measured on it.
class NegativePreviewBase {
  const NegativePreviewBase({
    required this.width,
    required this.height,
    required this.rgb,
    required this.bounds,
  });

  final int width;
  final int height;
  final Uint8List rgb;
  final NegativeBounds bounds;
}

/// Decodes a preview JPEG (the thumbnail or preview cache's) and shrinks
/// it to at most [maxDim] on the long edge. Null when it is not an image.
NegativePreviewBase? decodeNegativePreviewBase(
  ({Uint8List jpeg, int maxDim}) args,
) {
  var image = img.decodeImage(args.jpeg);
  if (image == null) {
    return null;
  }
  if (math.max(image.width, image.height) > args.maxDim) {
    image = image.width >= image.height
        ? img.copyResize(image, width: args.maxDim)
        : img.copyResize(image, height: args.maxDim);
  }
  final rgb = image.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb);
  final bytes = Uint8List.fromList(rgb);
  return NegativePreviewBase(
    width: image.width,
    height: image.height,
    rgb: bytes,
    bounds: analyzeNegativeBounds(bytes, image.width, image.height),
  );
}

/// The preview converted with [params], as RGBA bytes for
/// `decodeImageFromPixels`. With `params.enabled` false the original
/// comes back untouched — the dialog's hold-to-compare.
Uint8List renderNegativePreviewRgba(
  ({NegativePreviewBase base, NegativeParams params}) args,
) {
  final base = args.base;
  final buffer = Float32List(base.rgb.length);
  for (var i = 0; i < buffer.length; i++) {
    buffer[i] = base.rgb[i].toDouble();
  }
  applyNegative(buffer, args.params, base.bounds);
  final rgba = Uint8List(base.width * base.height * 4);
  for (var i = 0, j = 0; i < buffer.length; i += 3, j += 4) {
    rgba[j] = buffer[i].round().clamp(0, 255);
    rgba[j + 1] = buffer[i + 1].round().clamp(0, 255);
    rgba[j + 2] = buffer[i + 2].round().clamp(0, 255);
    rgba[j + 3] = 255;
  }
  return rgba;
}

/// The path [convertNegativeFile] writes for [sourcePath]: the source's
/// stem plus `_Positive.tiff` in the same folder, numbered when taken.
String positivePathFor(String sourcePath) {
  final dir = p.dirname(sourcePath);
  final stem = p.basenameWithoutExtension(sourcePath);
  var candidate = p.join(dir, '${stem}_Positive.tiff');
  var n = 2;
  while (File(candidate).existsSync()) {
    candidate = p.join(dir, '${stem}_Positive ($n).tiff');
    n++;
  }
  return candidate;
}

/// Decodes the photo at [args.path] at full resolution (the sensor data
/// for a RAW, never the embedded JPEG), converts it with [args.params]
/// against bounds measured on a 1080 px reference, and writes the
/// 16-bit TIFF. Returns the file written. Throws with a readable message
/// when the source cannot be decoded.
String convertNegativeFile(({String path, NegativeParams params}) args) {
  final decoded = decodeSourceImage(
    args.path,
    embeddedJpeg: false,
    fastPreview: false,
  );
  if (decoded == null) {
    throw StateError('could not decode ${p.basename(args.path)}');
  }
  final bounds = analyzeNegativeBoundsDownscaled(
    decoded.rgbBytes,
    decoded.width,
    decoded.height,
  );
  final samples = convertNegativeRgb16(decoded.rgbBytes, args.params, bounds);
  final image = img.Image.fromBytes(
    width: decoded.width,
    height: decoded.height,
    bytes: samples.buffer,
    numChannels: 3,
    format: img.Format.uint16,
    order: img.ChannelOrder.rgb,
  );
  final out = positivePathFor(args.path);
  File(out).writeAsBytesSync(img.encodeTiff(image));
  return out;
}
