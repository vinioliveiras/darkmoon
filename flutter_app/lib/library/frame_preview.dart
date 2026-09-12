// The Albums "Frame image" dialog's workers (2026-09-13) — plain
// top-level functions so `compute` can run them off the UI thread: the
// preview (a cached preview JPEG shrunk once, then framed again per
// control change) and the output path the real save uses. The real save
// goes through the export pipeline (`ExportRequest.frame`), so the file
// is the edited photo at full size with the frame composed in.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../export/frame.dart';

/// The dialog's preview source: the photo shrunk to [width] x [height].
class FramePreviewBase {
  const FramePreviewBase({
    required this.width,
    required this.height,
    required this.rgb,
  });

  final int width;
  final int height;
  final Uint8List rgb;
}

/// Decodes a preview JPEG (the preview or thumbnail cache's) and shrinks
/// it to at most [maxDim] on the long edge. Null when it is not an image.
FramePreviewBase? decodeFramePreviewBase(({Uint8List jpeg, int maxDim}) args) {
  var image = img.decodeImage(args.jpeg);
  if (image == null) {
    return null;
  }
  if (math.max(image.width, image.height) > args.maxDim) {
    image = image.width >= image.height
        ? img.copyResize(image, width: args.maxDim)
        : img.copyResize(image, height: args.maxDim);
  }
  final rgb = image
      .convert(numChannels: 3)
      .getBytes(order: img.ChannelOrder.rgb);
  return FramePreviewBase(
    width: image.width,
    height: image.height,
    rgb: Uint8List.fromList(rgb),
  );
}

/// The preview framed with [options], as RGBA bytes plus its size for
/// `decodeImageFromPixels`.
({int width, int height, Uint8List rgba}) renderFramePreviewRgba(
  ({FramePreviewBase base, FrameOptions options}) args,
) {
  final base = args.base;
  final photo = img.Image.fromBytes(
    width: base.width,
    height: base.height,
    bytes: Uint8List.fromList(base.rgb).buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final framed = applyFrame(photo, args.options);
  final rgb = framed.getBytes(order: img.ChannelOrder.rgb);
  final rgba = Uint8List(framed.width * framed.height * 4);
  for (var i = 0, j = 0; i < rgb.length; i += 3, j += 4) {
    rgba[j] = rgb[i];
    rgba[j + 1] = rgb[i + 1];
    rgba[j + 2] = rgb[i + 2];
    rgba[j + 3] = 255;
  }
  return (width: framed.width, height: framed.height, rgba: rgba);
}

/// The path the framed file takes for [sourcePath]: the source's stem
/// plus `_Framed.<extension>` in the same folder, numbered when taken —
/// Solstice's `_Collage` naming, for one picture.
String framedPathFor(String sourcePath, String extension) {
  final dir = p.dirname(sourcePath);
  final stem = p.basenameWithoutExtension(sourcePath);
  var candidate = p.join(dir, '${stem}_Framed.$extension');
  var n = 2;
  while (File(candidate).existsSync()) {
    candidate = p.join(dir, '${stem}_Framed ($n).$extension');
    n++;
  }
  return candidate;
}
