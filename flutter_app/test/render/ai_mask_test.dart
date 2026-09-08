import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/mask.dart';

/// Builds a map whose value is [value] everywhere, at [width] x [height].
AiMaskMap flatMap(int width, int height, int value) => AiMaskMap(
  width: width,
  height: height,
  data: Uint8List(width * height)..fillRange(0, width * height, value),
);

void main() {
  group('AI mask types without a map', () {
    // The normal state for the first render after adding one of these:
    // inference is still running. It has to render as "no mask", not as a
    // full-coverage one, or a photo would flash the mask's adjustments
    // over the whole frame every time.
    for (final type in aiMaskTypes) {
      test('$type covers nothing until its map arrives', () {
        final mask = MaskLayer(id: 'm', name: 'Mask', type: type);
        final alpha = computeMaskAlpha(mask, 4, 4);
        expect(alpha.every((v) => v == 0.0), isTrue);
      });
    }
  });

  group('segmentation masks', () {
    test('take their alpha straight from the map', () {
      const mask = MaskLayer(id: 'm', name: 'Mask', type: MaskType.sky);
      final alpha = computeMaskAlpha(
        mask,
        2,
        2,
        aiMap: AiMaskMap(
          width: 2,
          height: 2,
          data: Uint8List.fromList([0, 255, 128, 255]),
        ),
      );
      expect(alpha[0], closeTo(0.0, 1e-6));
      expect(alpha[1], closeTo(1.0, 1e-6));
      expect(alpha[2], closeTo(128 / 255, 1e-6));
      expect(alpha[3], closeTo(1.0, 1e-6));
    });

    test('rescale a map that is smaller than the render', () {
      const mask = MaskLayer(id: 'm', name: 'Mask', type: MaskType.foreground);
      final alpha = computeMaskAlpha(mask, 8, 8, aiMap: flatMap(2, 2, 255));
      expect(alpha.length, 64);
      expect(alpha.every((v) => (v - 1.0).abs() < 1e-6), isTrue);
    });

    test('respect opacity and inversion like every other mask type', () {
      final map = flatMap(2, 2, 255);
      const half = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.foreground,
        opacity: 40,
      );
      expect(computeMaskAlpha(half, 2, 2, aiMap: map)[0], closeTo(0.4, 1e-6));

      const inverted = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.foreground,
        inverted: true,
      );
      expect(computeMaskAlpha(inverted, 2, 2, aiMap: map)[0], closeTo(0, 1e-6));
    });
  });

  group('MaskType.depth', () {
    MaskLayer depthMask(DepthGeometry geometry) =>
        MaskLayer(id: 'm', name: 'Mask', type: MaskType.depth, depth: geometry);

    /// A one-pixel-per-column ramp from far (0) to near (255).
    AiMaskMap rampMap(List<int> values) =>
        AiMaskMap(width: values.length, height: 1, data: Uint8List.fromList(values));

    test('selects the band between far and near at full strength', () {
      final alpha = computeMaskAlpha(
        depthMask(const DepthGeometry(near: 1.0, far: 0.5, feather: 0)),
        4,
        1,
        aiMap: rampMap([0, 96, 160, 255]),
      );
      expect(alpha[0], 0.0); // depth 0.00 — behind the band
      expect(alpha[1], 0.0); // depth 0.38 — still behind it
      expect(alpha[2], 1.0); // depth 0.63 — inside
      expect(alpha[3], 1.0); // depth 1.00 — inside
    });

    test('near and far are interchangeable — the band is the same either way', () {
      final map = rampMap([0, 96, 160, 255]);
      final ascending = computeMaskAlpha(
        depthMask(const DepthGeometry(near: 0.5, far: 1.0, feather: 0)),
        4,
        1,
        aiMap: map,
      );
      final descending = computeMaskAlpha(
        depthMask(const DepthGeometry(near: 1.0, far: 0.5, feather: 0)),
        4,
        1,
        aiMap: map,
      );
      expect(ascending, descending);
    });

    test('feather fades out over its own fraction of the depth range', () {
      // Band is 0.6..1.0 with a 0.2 fade, so depth 0.5 sits halfway down
      // the ramp and depth 0.4 is past its end.
      final alpha = computeMaskAlpha(
        depthMask(const DepthGeometry(near: 1.0, far: 0.6, feather: 20)),
        3,
        1,
        aiMap: rampMap([102, 128, 179]),
      );
      expect(alpha[0], closeTo(0.0, 0.02)); // 0.40 — beyond the fade
      expect(alpha[1], closeTo(0.5, 0.02)); // 0.50 — mid-fade
      expect(alpha[2], closeTo(1.0, 1e-6)); // 0.70 — inside the band
    });

    test('a zero feather is a hard edge, not a fade to nothing', () {
      final alpha = computeMaskAlpha(
        depthMask(const DepthGeometry(near: 1.0, far: 0.9, feather: 0)),
        2,
        1,
        aiMap: rampMap([228, 255]),
      );
      expect(alpha[0], 0.0); // 0.894 — just outside
      expect(alpha[1], 1.0);
    });
  });

  group('AiMaskMap resampling', () {
    test('samples an upscaled map without shifting it off-centre', () {
      // A left-half/right-half split has to stay a split down the middle
      // when the map is stretched to eight times its width.
      final map = AiMaskMap(
        width: 4,
        height: 1,
        data: Uint8List.fromList([255, 255, 0, 0]),
      );
      const mask = MaskLayer(id: 'm', name: 'Mask', type: MaskType.sky);
      final alpha = computeMaskAlpha(mask, 32, 1, aiMap: map);
      expect(alpha.first, closeTo(1.0, 1e-6));
      expect(alpha.last, closeTo(0.0, 1e-6));
      // The crossing lands within a map pixel of the halfway mark.
      final crossing = alpha.indexWhere((v) => v < 0.5);
      expect(crossing, greaterThan(32 ~/ 2 - 8));
      expect(crossing, lessThan(32 ~/ 2 + 8));
    });
  });
}
