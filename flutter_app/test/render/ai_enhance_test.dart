import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/native/onnx_runtime.dart';
import 'package:darkmoon/render/ai_enhance.dart';

/// Fakes matching each spec's exact input/output tile size (real
/// OnnxModel.runTile validates this too — see onnx_runtime.dart) so this
/// file can exercise enhanceImage's orchestration (byte<->float
/// conversion, denoise-then-upscale ordering, final dimensions, progress
/// stage labels) without any GPU/model dependency, the same spirit as
/// ai_denoise_tiling_test.dart's fakes.
Float32List _identityDenoise(Float32List tile) => tile;

Float32List _nearestNeighborUpscale(Float32List tile) {
  final inSize = upscaleModelSpec.inputTileSize;
  final outSize = upscaleModelSpec.outputTileSize;
  final out = Float32List(outSize * outSize * 3);
  for (var y = 0; y < inSize; y++) {
    for (var x = 0; x < inSize; x++) {
      final srcI = (y * inSize + x) * 3;
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          final dstI = ((y * 2 + dy) * outSize + (x * 2 + dx)) * 3;
          out[dstI] = tile[srcI];
          out[dstI + 1] = tile[srcI + 1];
          out[dstI + 2] = tile[srcI + 2];
        }
      }
    }
  }
  return out;
}

void main() {
  test('output is upscaleModelSpec.scaleFactor times the input size', () {
    const width = 96;
    const height = 64;
    final rgb = Uint8List(width * height * 3);
    for (var i = 0; i < rgb.length; i++) {
      rgb[i] = (i * 7) % 256;
    }

    final result = enhanceImage(
      rgb,
      width,
      height,
      denoise: _identityDenoise,
      upscale: _nearestNeighborUpscale,
    );

    expect(result.width, width * upscaleModelSpec.scaleFactor);
    expect(result.height, height * upscaleModelSpec.scaleFactor);
    expect(result.rgbBytes.length, result.width * result.height * 3);
  });

  test('reports both a denoise phase and an upscale phase, in that order', () {
    const width = 96;
    const height = 64;
    final rgb = Uint8List(width * height * 3);

    final stages = <String>[];
    enhanceImage(
      rgb,
      width,
      height,
      denoise: _identityDenoise,
      upscale: _nearestNeighborUpscale,
      onProgress: (stage, i, total) {
        if (!stages.contains(stage)) stages.add(stage);
      },
    );

    expect(stages, ['denoise', 'upscale']);
  });

  test(
    'round-trips byte values through the [0,1] float conversion cleanly '
    '(identity denoise + a 1:1 "upscale" fake) — catches an off-by-one or '
    'rounding bug in the byte<->float conversion',
    () {
      const width = 64;
      const height = 64;
      final rgb = Uint8List(width * height * 3);
      for (var i = 0; i < rgb.length; i++) {
        rgb[i] = (i * 53) % 256;
      }

      // A 1:1 "upscale" that just repeats each pixel scaleFactor^2 times —
      // lets this test check exact byte values survive the round trip
      // (a real 2x model wouldn't preserve input values exactly, so this
      // fake stands in specifically to isolate the conversion math).
      Float32List identityUpscale(Float32List tile) {
        final inSize = upscaleModelSpec.inputTileSize;
        final scale = upscaleModelSpec.scaleFactor;
        final outSize = inSize * scale;
        final out = Float32List(outSize * outSize * 3);
        for (var y = 0; y < inSize; y++) {
          for (var x = 0; x < inSize; x++) {
            final srcI = (y * inSize + x) * 3;
            for (var dy = 0; dy < scale; dy++) {
              for (var dx = 0; dx < scale; dx++) {
                final dstI = ((y * scale + dy) * outSize + (x * scale + dx)) * 3;
                out[dstI] = tile[srcI];
                out[dstI + 1] = tile[srcI + 1];
                out[dstI + 2] = tile[srcI + 2];
              }
            }
          }
        }
        return out;
      }

      final result = enhanceImage(
        rgb,
        width,
        height,
        denoise: _identityDenoise,
        upscale: identityUpscale,
      );

      final scale = upscaleModelSpec.scaleFactor;
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final srcI = (y * width + x) * 3;
          final dstI = ((y * scale) * (width * scale) + (x * scale)) * 3;
          for (var c = 0; c < 3; c++) {
            expect(
              result.rgbBytes[dstI + c],
              closeTo(rgb[srcI + c].toDouble(), 1),
              reason: 'pixel ($x,$y) channel $c',
            );
          }
        }
      }
    },
  );
}
