import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/ai_denoise_tiling.dart';

void main() {
  test(
    'identity processTile round-trips the image unchanged '
    '(proves the split/crop geometry and blend weights are correct, '
    'independent of any real model)',
    () {
      const width = 100;
      const height = 70;
      final rgb = Float32List(width * height * 3);
      for (var i = 0; i < rgb.length; i++) {
        // Deterministic but non-trivial content — not a flat image, so a
        // geometry bug (off-by-one tile placement, wrong crop) would show
        // up as a real mismatch rather than trivially matching by luck.
        rgb[i] = ((i * 37) % 256) / 255.0;
      }

      final result = denoiseTiled(
        rgb,
        width,
        height,
        inputTileSize: 32,
        overlap: 8,
        scaleFactor: 1,
        processTile: (tile) => tile,
      );

      expect(result.length, rgb.length);
      for (var i = 0; i < rgb.length; i++) {
        expect(
          result[i],
          closeTo(rgb[i], 1e-4),
          reason: 'mismatch at index $i',
        );
      }
    },
  );

  test(
    'overlapping tiles cross-fade smoothly — no hard seam at a tile '
    'boundary',
    () {
      // Wide enough for exactly two tile steps (32 input tile, 8 overlap
      // -> step 24: tiles at x0=0 and x0=24, sharing input columns
      // [24,32)), short enough to keep the test fast/obvious.
      const width = 56;
      const height = 32;
      final rgb = Float32List(width * height * 3);

      var callCount = 0;
      Float32List distinctFlatPerTile(Float32List tile) {
        // Each tile call returns a flat color unrelated to its input and
        // distinct from the previous tile's — if the seam weren't
        // blended, crossing from one tile's region to the next would jump
        // straight from one flat value to the other in a single pixel.
        final value = (callCount++) * 0.4;
        return Float32List(tile.length)..fillRange(0, tile.length, value);
      }

      final result = denoiseTiled(
        rgb,
        width,
        height,
        inputTileSize: 32,
        overlap: 8,
        scaleFactor: 1,
        processTile: distinctFlatPerTile,
      );

      // Sample the red channel along the row through the overlap band
      // (output columns 24..31, tile size 1:1 since scaleFactor is 1) and
      // confirm it's a monotonic ramp between the two tiles' flat values,
      // not a single-pixel step.
      const y = 16;
      final samples = <double>[
        for (var x = 24; x < 32; x++) result[(y * width + x) * 3],
      ];
      for (var i = 1; i < samples.length; i++) {
        expect(
          samples[i],
          greaterThanOrEqualTo(samples[i - 1] - 1e-6),
          reason: 'blend ramp should be monotonic, got $samples',
        );
      }
      // A real cross-fade spans more than just the two endpoints — assert
      // at least one interior sample sits strictly between them (a hard
      // seam would jump directly from the first tile's flat value to the
      // second's with nothing in between).
      final first = samples.first;
      final last = samples.last;
      final hasIntermediate = samples.any(
        (v) => v > first + 1e-6 && v < last - 1e-6,
      );
      expect(
        hasIntermediate,
        isTrue,
        reason: 'expected a smooth ramp between $first and $last, got $samples',
      );
    },
  );

  test('scaleFactor 2 (upscale) produces a correctly-sized, sane output', () {
    const width = 48;
    const height = 40;
    final rgb = Float32List(width * height * 3);
    for (var i = 0; i < rgb.length; i++) {
      rgb[i] = ((i * 53) % 256) / 255.0;
    }

    Float32List fakeUpscale(Float32List tile) {
      // A trivial (wrong, but shape-correct) 2x "upscale": repeat each
      // input pixel 2x2 — enough to sanity-check the tiling geometry
      // without needing a real model.
      const inSize = 16;
      const outSize = inSize * 2;
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

    final result = denoiseTiled(
      rgb,
      width,
      height,
      inputTileSize: 16,
      overlap: 4,
      scaleFactor: 2,
      processTile: fakeUpscale,
    );

    expect(result.length, width * 2 * height * 2 * 3);
    for (final v in result) {
      expect(v.isFinite, isTrue);
      expect(v, inInclusiveRange(-0.01, 1.01));
    }
  });

  test('throws if processTile returns the wrong size', () {
    final rgb = Float32List(32 * 32 * 3);
    expect(
      () => denoiseTiled(
        rgb,
        32,
        32,
        inputTileSize: 32,
        overlap: 8,
        scaleFactor: 1,
        processTile: (tile) => Float32List(10),
      ),
      throwsStateError,
    );
  });

  test('reports progress once per tile', () {
    const width = 56;
    const height = 32;
    final rgb = Float32List(width * height * 3);
    final progressCalls = <(int, int)>[];

    denoiseTiled(
      rgb,
      width,
      height,
      inputTileSize: 32,
      overlap: 8,
      scaleFactor: 1,
      processTile: (tile) => tile,
      onProgress: (i, total) => progressCalls.add((i, total)),
    );

    // 56x32 at tileSize 32 / overlap 8 (step 24) -> 2 tiles across
    // (56 needs one extra step past the first 32) x 1 down (32 fits in a
    // single tile exactly).
    expect(progressCalls.length, 2);
    expect(progressCalls.last, (2, 2));
  });
}
