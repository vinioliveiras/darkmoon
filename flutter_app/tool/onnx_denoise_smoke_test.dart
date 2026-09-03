// Standalone smoke test for the ONNX denoise/upscale plumbing
// (lib/native/onnx_runtime.dart) — Phase A's exit criterion: load a real
// model, run one real tile through it, confirm the output is visually
// sane, before building tiling/cache/UI on top of it.
//
// Crops a tile from a real photo, runs it through OnnxModel.forSpec(...),
// and writes both the input and output tiles as PNGs for visual
// comparison. Prints which execution provider actually ran — see
// OnnxModel._providerChain for the order tried per platform, and set
// DARKMOON_ONNX_EP=webgpu|directml|cpu to force one.
//
// Usage:
//   dart run tool/onnx_denoise_smoke_test.dart [denoise|upscale] [image] [x] [y]
// Defaults: denoise, assets/splash/featured.jpg, a roughly-centered tile.
import 'dart:io';
import 'dart:typed_data';

import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final which = args.isNotEmpty ? args[0] : 'denoise';
  final spec = switch (which) {
    'denoise' => denoiseModelSpec,
    'upscale' => upscaleModelSpec,
    _ => throw ArgumentError(
      'first arg must be "denoise" or "upscale", got "$which"',
    ),
  };
  final imagePath = args.length > 1 ? args[1] : 'assets/splash/featured.jpg';

  final bytes = File(imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    stderr.writeln('Could not decode $imagePath');
    exit(2);
  }
  final full = decoded.convert(format: img.Format.uint8, numChannels: 3);

  final tileSize = spec.inputTileSize;
  final defaultX = ((full.width - tileSize) / 2).floor().clamp(
    0,
    full.width - tileSize,
  );
  final defaultY = ((full.height - tileSize) / 2).floor().clamp(
    0,
    full.height - tileSize,
  );
  final x = args.length > 2 ? int.parse(args[2]) : defaultX;
  final y = args.length > 3 ? int.parse(args[3]) : defaultY;

  if (x < 0 ||
      y < 0 ||
      x + tileSize > full.width ||
      y + tileSize > full.height) {
    stderr.writeln(
      'Tile ($x,$y) ${tileSize}x$tileSize does not fit in '
      '${full.width}x${full.height} image',
    );
    exit(2);
  }

  // ignore: avoid_print
  print(
    'Model: ${spec.fileName} (input ${tileSize}x$tileSize, '
    'output ${spec.outputTileSize}x${spec.outputTileSize})',
  );
  // ignore: avoid_print
  print('Source: $imagePath (${full.width}x${full.height}), tile at ($x,$y)');

  // Pack the crop into normalized [0,1] float RGB — the standard
  // convention for this class of PyTorch-exported restoration model
  // (BasicSR/NAFNet, Real-ESRGAN both just do img/255, no further
  // mean/std normalization baked outside the graph).
  final inputTile = Float32List(tileSize * tileSize * 3);
  for (var ty = 0; ty < tileSize; ty++) {
    for (var tx = 0; tx < tileSize; tx++) {
      final pixel = full.getPixel(x + tx, y + ty);
      final i = (ty * tileSize + tx) * 3;
      inputTile[i] = pixel.r / 255.0;
      inputTile[i + 1] = pixel.g / 255.0;
      inputTile[i + 2] = pixel.b / 255.0;
    }
  }

  final loadSw = Stopwatch()..start();
  final model = OnnxModel.forSpec(spec);
  loadSw.stop();
  // ignore: avoid_print
  print(
    'Session ready in ${loadSw.elapsedMilliseconds}ms — '
    'running on ${model.usingGpu ? "GPU (${model.provider.label})" : "CPU (fallback)"}',
  );

  final runSw = Stopwatch()..start();
  final outputTile = model.runTile(inputTile);
  runSw.stop();
  // ignore: avoid_print
  print('runTile: ${runSw.elapsedMilliseconds}ms');

  var minV = double.infinity, maxV = double.negativeInfinity, sum = 0.0;
  for (final v in outputTile) {
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
    sum += v;
  }
  // ignore: avoid_print
  print(
    'Output stats: min=$minV max=$maxV mean=${sum / outputTile.length} '
    '(sane range is roughly [0,1], mean somewhere near the input tile'
    ' brightness — wildly outside that suggests a normalization mismatch)',
  );

  final outSize = spec.outputTileSize;
  final outImage = img.Image(width: outSize, height: outSize, numChannels: 3);
  for (var ty = 0; ty < outSize; ty++) {
    for (var tx = 0; tx < outSize; tx++) {
      final i = (ty * outSize + tx) * 3;
      outImage.setPixelRgb(
        tx,
        ty,
        (outputTile[i] * 255.0).clamp(0, 255).round(),
        (outputTile[i + 1] * 255.0).clamp(0, 255).round(),
        (outputTile[i + 2] * 255.0).clamp(0, 255).round(),
      );
    }
  }

  final inImage = img.Image(width: tileSize, height: tileSize, numChannels: 3);
  for (var ty = 0; ty < tileSize; ty++) {
    for (var tx = 0; tx < tileSize; tx++) {
      final i = (ty * tileSize + tx) * 3;
      inImage.setPixelRgb(
        tx,
        ty,
        (inputTile[i] * 255.0).round(),
        (inputTile[i + 1] * 255.0).round(),
        (inputTile[i + 2] * 255.0).round(),
      );
    }
  }

  File('onnx_smoke_${which}_in.png').writeAsBytesSync(img.encodePng(inImage));
  File('onnx_smoke_${which}_out.png').writeAsBytesSync(img.encodePng(outImage));
  // ignore: avoid_print
  print('OK -> onnx_smoke_${which}_in.png / onnx_smoke_${which}_out.png');
}
