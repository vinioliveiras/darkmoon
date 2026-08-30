import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/native/onnx_runtime.dart' show pmridDenoiseModelSpec;
import 'package:darkmoon/render/pmrid_denoise.dart';

/// Fakes matching pmridDenoiseModelSpec's exact input/output tile size —
/// same spirit as ai_enhance_test.dart's fakes, exercising
/// denoisePmridRggb's own orchestration (the anchor-scale
/// multiply/divide, tiling, dimensions) without a real ONNX model.
Float32List _identity(Float32List tile) => tile;

Float32List _zero(Float32List tile) => Float32List(tile.length);

void main() {
  test(
    'identity model round-trips the RGGB buffer through the anchor-scale '
    'multiply/divide unchanged',
    () {
      const width = 40; // smaller than one tile — exercises the edge-clamp
      const height = 30; // padding path, not just a single full tile.
      final rggb = Float32List(width * height * 4);
      for (var i = 0; i < rggb.length; i++) {
        rggb[i] = ((i * 29) % 100) / 100.0;
      }

      final result = denoisePmridRggb(
        rggb,
        width,
        height,
        denoise: _identity,
      );

      expect(result.length, rggb.length);
      for (var i = 0; i < rggb.length; i++) {
        expect(result[i], closeTo(rggb[i], 1e-4), reason: 'mismatch at $i');
      }
    },
  );

  test('a model that zeroes every tile produces an all-zero result (no blend step, unlike sRGB denoise)', () {
    const width = 32;
    const height = 32;
    final rggb = Float32List(width * height * 4);
    for (var i = 0; i < rggb.length; i++) {
      rggb[i] = 0.5;
    }

    final result = denoisePmridRggb(rggb, width, height, denoise: _zero);

    for (final v in result) {
      expect(v, 0.0);
    }
  });

  test('output stays same resolution as the input (no scale factor, unlike upscale)', () {
    const width = 48;
    const height = 64;
    final rggb = Float32List(width * height * 4);

    final result = denoisePmridRggb(rggb, width, height, denoise: _identity);

    expect(result.length, width * height * 4);
  });

  test('forwards per-tile progress', () {
    const width = 40;
    const height = 30;
    final rggb = Float32List(width * height * 4);
    final calls = <(int, int)>[];

    denoisePmridRggb(
      rggb,
      width,
      height,
      denoise: _identity,
      onProgress: (i, total) => calls.add((i, total)),
    );

    expect(calls, isNotEmpty);
    expect(calls.last.$1, calls.last.$2);
  });

  test('uses pmridDenoiseModelSpec\'s tile geometry (4 channels, no upscale)', () {
    expect(pmridDenoiseModelSpec.channels, 4);
    expect(pmridDenoiseModelSpec.scaleFactor, 1);
  });
}
