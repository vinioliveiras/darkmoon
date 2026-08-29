// End-to-end smoke test: real model + real tiling on a full-resolution
// image (not a single tile) — proves Phase A (onnx_runtime.dart) and
// Phase B (ai_denoise_tiling.dart) work together, seams and all.
//
// Usage: dart run tool/onnx_full_image_smoke_test.dart [denoise|upscale] [image]
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:darkmoon/render/ai_denoise_tiling.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final which = args.isNotEmpty ? args[0] : 'denoise';
  final spec = switch (which) {
    'denoise' => denoiseModelSpec,
    'upscale' => upscaleModelSpec,
    _ => throw ArgumentError('first arg must be "denoise" or "upscale"'),
  };
  final imagePath = args.length > 1 ? args[1] : 'assets/splash/featured.jpg';

  final decoded = img.decodeImage(File(imagePath).readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('Could not decode $imagePath');
    exit(2);
  }
  final full = decoded.convert(format: img.Format.uint8, numChannels: 3);
  // ignore: avoid_print
  print('Source: $imagePath (${full.width}x${full.height})');

  final rgb = Float32List(full.width * full.height * 3);
  for (var y = 0; y < full.height; y++) {
    for (var x = 0; x < full.width; x++) {
      final pixel = full.getPixel(x, y);
      final i = (y * full.width + x) * 3;
      rgb[i] = pixel.r / 255.0;
      rgb[i + 1] = pixel.g / 255.0;
      rgb[i + 2] = pixel.b / 255.0;
    }
  }

  final model = OnnxModel.forSpec(spec);
  // ignore: avoid_print
  print('Model ready — running on ${model.usingGpu ? "GPU" : "CPU"}');

  final sw = Stopwatch()..start();
  var lastPct = -1;
  final result = denoiseTiled(
    rgb,
    full.width,
    full.height,
    inputTileSize: spec.inputTileSize,
    overlap: spec.inputTileSize ~/ 8,
    scaleFactor: spec.scaleFactor,
    processTile: model.runTile,
    onProgress: (i, total) {
      final pct = (i * 100 ~/ total);
      if (pct != lastPct) {
        lastPct = pct;
        stdout.write('\r  tile $i/$total ($pct%)');
      }
    },
  );
  stdout.writeln();
  sw.stop();
  // ignore: avoid_print
  print('denoiseTiled: ${sw.elapsedMilliseconds}ms total');

  final outWidth = full.width * spec.scaleFactor;
  final outHeight = full.height * spec.scaleFactor;
  final outImage = img.Image(width: outWidth, height: outHeight, numChannels: 3);
  for (var y = 0; y < outHeight; y++) {
    for (var x = 0; x < outWidth; x++) {
      final i = (y * outWidth + x) * 3;
      outImage.setPixelRgb(
        x,
        y,
        (result[i] * 255.0).clamp(0, 255).round(),
        (result[i + 1] * 255.0).clamp(0, 255).round(),
        (result[i + 2] * 255.0).clamp(0, 255).round(),
      );
    }
  }
  final outPath = 'onnx_full_${which}_out.png';
  File(outPath).writeAsBytesSync(img.encodePng(outImage));
  // ignore: avoid_print
  print('OK -> $outPath (${outWidth}x$outHeight)');
}
