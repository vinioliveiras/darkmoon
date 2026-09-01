// One-off validation (NOT a permanent smoke test) for the DDColor
// colorization port (item 37, 2026-09-01) — compares against the Python
// reference pipeline's own output on the same source image.
//
// Usage: dart run tool/ddcolor_test.dart <grayscale-or-color.png> [out.png]
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:darkmoon/render/colorize.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final path = args[0];
  final outPath = args.length > 1 ? args[1] : 'ddcolor_dart_out.png';

  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $path');
    exit(2);
  }
  final full = decoded.convert(format: img.Format.uint8, numChannels: 3);
  final rgbBytes = full.getBytes(order: img.ChannelOrder.rgb);
  // ignore: avoid_print
  print('Source: $path (${full.width}x${full.height})');

  final model = OnnxModel.forSpec(ddcolorModelSpec);
  // ignore: avoid_print
  print('Model ready — running on ${model.usingGpu ? "GPU" : "CPU"}');

  final sw = Stopwatch()..start();
  final result = colorizeImage(
    Uint8List.fromList(rgbBytes),
    full.width,
    full.height,
    runModel: (tile) => model.runToChannels(tile, 2),
    modelInputSize: ddcolorModelSpec.inputTileSize,
  );
  sw.stop();
  // ignore: avoid_print
  print('colorizeImage: ${sw.elapsedMilliseconds}ms');

  final outImage = img.Image.fromBytes(
    width: full.width,
    height: full.height,
    bytes: result.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  File(outPath).writeAsBytesSync(img.encodePng(outImage));
  // ignore: avoid_print
  print('OK -> $outPath');
}
