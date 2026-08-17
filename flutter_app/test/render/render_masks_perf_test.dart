import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/mask.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

void main() {
  group('renderRgbWithMasks — no-op mask skipping', () {
    Uint8List flatGray(int width, int height, int value) {
      final buf = Uint8List(width * height * 3);
      buf.fillRange(0, buf.length, value);
      return buf;
    }

    test('a mask with no values and identity curves is a no-op, same as '
        'not having it at all', () {
      final src = flatGray(4, 4, 120);
      const emptyMask = MaskLayer(
        id: 'm',
        name: 'Empty',
        type: MaskType.radialGradient,
      );
      final withEmptyMask = renderRgbWithMasks(
        4,
        4,
        src,
        const RenderParams(),
        [emptyMask],
      );
      final withoutMasks = renderRgbWithMasks(
        4,
        4,
        src,
        const RenderParams(),
        const [],
      );
      expect(withEmptyMask, withoutMasks);
    });

    test('a mask with real values still applies its effect', () {
      final src = flatGray(8, 8, 120);
      final maskWithEffect = MaskLayer(
        id: 'm',
        name: 'Bright',
        type: MaskType.radialGradient,
        radial: const RadialGradientGeometry(
          centerX: 0.5,
          centerY: 0.5,
          radius: 10,
          feather: 0,
        ),
        values: const {'Exposure': 50},
      );
      final result = renderRgbWithMasks(8, 8, src, const RenderParams(), [
        maskWithEffect,
      ]);
      final withoutMasks = renderRgbWithMasks(
        8,
        8,
        src,
        const RenderParams(),
        const [],
      );
      expect(result, isNot(withoutMasks));
    });

    test('a disabled mask (even with values) is still skipped', () {
      final src = flatGray(4, 4, 120);
      final disabledMask = MaskLayer(
        id: 'm',
        name: 'Disabled',
        type: MaskType.radialGradient,
        enabled: false,
        values: const {'Exposure': 80},
      );
      final result = renderRgbWithMasks(4, 4, src, const RenderParams(), [
        disabledMask,
      ]);
      final withoutMasks = renderRgbWithMasks(
        4,
        4,
        src,
        const RenderParams(),
        const [],
      );
      expect(result, withoutMasks);
    });
  });
}
