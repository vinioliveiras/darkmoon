import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/mask.dart';

void main() {
  group('MaskType.luminance', () {
    Float32List grayRgb(List<double> lumas) {
      final rgb = Float32List(lumas.length * 3);
      for (var i = 0; i < lumas.length; i++) {
        rgb[i * 3] = lumas[i];
        rgb[i * 3 + 1] = lumas[i];
        rgb[i * 3 + 2] = lumas[i];
      }
      return rgb;
    }

    test('selects pixels near the target luma at full alpha', () {
      const mask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.luminance,
        luminance: LuminanceGeometry(
          targetLuma: 200,
          tolerance: 10,
          feather: 0,
        ),
      );
      final rgb = grayRgb([200, 0]);
      final alpha = computeMaskAlpha(mask, 2, 1, sourceForColorRange: rgb);
      expect(alpha[0], 1.0);
      expect(alpha[1], 0.0);
    });

    test('feathers the falloff between core and cutoff', () {
      const mask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.luminance,
        luminance: LuminanceGeometry(
          targetLuma: 128,
          tolerance: 0,
          feather: 100,
        ),
      );
      // Distance grows with luma offset from 128; alpha should decrease
      // monotonically as the pixel gets further from the target.
      final rgb = grayRgb([128, 160, 220]);
      final alpha = computeMaskAlpha(mask, 3, 1, sourceForColorRange: rgb);
      expect(alpha[0], 1.0);
      expect(alpha[1], greaterThan(alpha[2]));
      expect(alpha[2], greaterThanOrEqualTo(0.0));
    });

    test('ignores color, only brightness', () {
      const mask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.luminance,
        luminance: LuminanceGeometry(targetLuma: 100, tolerance: 5, feather: 0),
      );
      // Two very different colors that share the same luma should both
      // be selected identically.
      final rgb = Float32List.fromList([100, 100, 100, 200, 20, 60]);
      final alpha = computeMaskAlpha(mask, 2, 1, sourceForColorRange: rgb);
      expect(alpha[0], 1.0);
      // The second pixel's luma (Rec.709-weighted) is far from 100, so it
      // should not be selected.
      expect(alpha[1], lessThan(1.0));
    });
  });

  group('MaskType.flow', () {
    test('a single stroke cannot exceed its own flow percentage', () {
      const stroke = BrushStroke(
        points: [BrushPoint(0.5, 0.5)],
        radius: 0.5,
        hardness: 1.0,
        erase: false,
        flow: 25,
      );
      const mask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.flow,
        brush: BrushGeometry(strokes: [stroke]),
      );
      final alpha = computeMaskAlpha(mask, 4, 4);
      for (final v in alpha) {
        expect(v, lessThanOrEqualTo(0.25 + 1e-6));
      }
      // The stroke is centered and covers the whole 4x4 canvas at full
      // hardness/radius, so the center pixel should reach ~25%.
      expect(alpha[5], closeTo(0.25, 1e-6));
    });

    test('repeated passes build up coverage beyond a single pass', () {
      const stroke = BrushStroke(
        points: [BrushPoint(0.5, 0.5)],
        radius: 0.5,
        hardness: 1.0,
        erase: false,
        flow: 25,
      );
      const twoStrokes = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.flow,
        brush: BrushGeometry(strokes: [stroke, stroke]),
      );
      final alpha = computeMaskAlpha(twoStrokes, 4, 4);
      // over-compositing 25% twice: 0.25 + 0.25 - 0.25*0.25 = 0.4375
      expect(alpha[5], closeTo(0.4375, 1e-6));
    });

    test('flow=100 matches a plain Brush stroke\'s full coverage', () {
      const stroke = BrushStroke(
        points: [BrushPoint(0.5, 0.5)],
        radius: 0.5,
        hardness: 1.0,
        erase: false,
      );
      const flowMask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.flow,
        brush: BrushGeometry(strokes: [stroke]),
      );
      const brushMask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.brush,
        brush: BrushGeometry(strokes: [stroke]),
      );
      final flowAlpha = computeMaskAlpha(flowMask, 4, 4);
      final brushAlpha = computeMaskAlpha(brushMask, 4, 4);
      for (var i = 0; i < flowAlpha.length; i++) {
        expect(flowAlpha[i], closeTo(brushAlpha[i], 1e-6));
      }
    });

    test('erase reduces existing coverage from a prior pass', () {
      const paintStroke = BrushStroke(
        points: [BrushPoint(0.5, 0.5)],
        radius: 0.5,
        hardness: 1.0,
        erase: false,
        flow: 100,
      );
      const eraseStroke = BrushStroke(
        points: [BrushPoint(0.5, 0.5)],
        radius: 0.5,
        hardness: 1.0,
        erase: true,
        flow: 50,
      );
      const mask = MaskLayer(
        id: 'm',
        name: 'Mask',
        type: MaskType.flow,
        brush: BrushGeometry(strokes: [paintStroke, eraseStroke]),
      );
      final alpha = computeMaskAlpha(mask, 4, 4);
      // Full deposit then 50% erase: 1.0 * (1 - 0.5) = 0.5
      expect(alpha[5], closeTo(0.5, 1e-6));
    });
  });
}
