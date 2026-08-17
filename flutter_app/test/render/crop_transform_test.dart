import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/crop_transform.dart';
import 'package:darkmoon/render/geometry.dart';

void main() {
  group('Matrix3', () {
    test('identity transforms points unchanged', () {
      final p = Matrix3.identity.transformPoint(3, 4);
      expect(p[0], closeTo(3, 1e-9));
      expect(p[1], closeTo(4, 1e-9));
    });

    test('invert() undoes a simple scale matrix', () {
      const scale2x = Matrix3([2, 0, 0, 0, 2, 0, 0, 0, 1]);
      final inv = scale2x.invert();
      final p = inv.transformPoint(10, 20);
      expect(p[0], closeTo(5, 1e-9));
      expect(p[1], closeTo(10, 1e-9));
    });

    test('invert() falls back to identity on a singular matrix', () {
      const singular = Matrix3([0, 0, 0, 0, 0, 0, 0, 0, 0]);
      final inv = singular.invert();
      expect(inv.m, Matrix3.identity.m);
    });
  });

  group('solveHomography', () {
    test('identity quad solves to the identity transform', () {
      final square = [
        [0.0, 0.0],
        [10.0, 0.0],
        [10.0, 10.0],
        [0.0, 10.0],
      ];
      final h = solveHomography(square, square);
      for (final corner in square) {
        final p = h.transformPoint(corner[0], corner[1]);
        expect(p[0], closeTo(corner[0], 1e-6));
        expect(p[1], closeTo(corner[1], 1e-6));
      }
    });

    test('maps a square to a scaled square correctly', () {
      final src = [
        [0.0, 0.0],
        [10.0, 0.0],
        [10.0, 10.0],
        [0.0, 10.0],
      ];
      final dst = [
        [0.0, 0.0],
        [20.0, 0.0],
        [20.0, 20.0],
        [0.0, 20.0],
      ];
      final h = solveHomography(src, dst);
      final p = h.transformPoint(5, 5);
      expect(p[0], closeTo(10, 1e-6));
      expect(p[1], closeTo(10, 1e-6));
    });
  });

  group('rotatePoint', () {
    test('90 degrees about origin maps (1,0) to (0,1)', () {
      final p = rotatePoint(1, 0, 0, 0, 3.14159265358979 / 2);
      expect(p[0], closeTo(0, 1e-6));
      expect(p[1], closeTo(1, 1e-6));
    });

    test('rotating about a non-origin center', () {
      final p = rotatePoint(1, 1, 1, 1, 3.14159265358979);
      expect(p[0], closeTo(1, 1e-6));
      expect(p[1], closeTo(1, 1e-6));
    });
  });

  group('CropTransformParams', () {
    test('default is identity', () {
      expect(const CropTransformParams().isIdentity, isTrue);
    });

    test('any non-default field breaks identity', () {
      expect(const CropTransformParams(straightenAngle: 1).isIdentity, isFalse);
      expect(const CropTransformParams(scale: 110).isIdentity, isFalse);
      expect(const CropTransformParams(cropLeft: 0.1).isIdentity, isFalse);
    });

    test('fromValues/toValues round-trip', () {
      const params = CropTransformParams(
        straightenAngle: 5,
        vertical: 10,
        horizontal: -10,
        aspect: 20,
        scale: 120,
        rotateQuarterTurns: 1,
        cropLeft: 0.1,
        cropTop: 0.2,
        cropRight: 0.9,
        cropBottom: 0.8,
      );
      final roundTripped = CropTransformParams.fromValues(params.toValues());
      expect(roundTripped.straightenAngle, params.straightenAngle);
      expect(roundTripped.vertical, params.vertical);
      expect(roundTripped.horizontal, params.horizontal);
      expect(roundTripped.aspect, params.aspect);
      expect(roundTripped.scale, params.scale);
      expect(roundTripped.rotateQuarterTurns, params.rotateQuarterTurns);
      expect(roundTripped.cropLeft, params.cropLeft);
      expect(roundTripped.cropTop, params.cropTop);
      expect(roundTripped.cropRight, params.cropRight);
      expect(roundTripped.cropBottom, params.cropBottom);
    });
  });

  group('applyCropTransform', () {
    Uint8List flatImage(int width, int height, int r, int g, int b) {
      final buf = Uint8List(width * height * 3);
      for (var p = 0; p < width * height; p++) {
        buf[p * 3] = r;
        buf[p * 3 + 1] = g;
        buf[p * 3 + 2] = b;
      }
      return buf;
    }

    test('identity params returns source unchanged (same buffer)', () {
      final src = flatImage(4, 4, 10, 20, 30);
      final result = applyCropTransform(src, 4, 4, const CropTransformParams());
      expect(result.width, 4);
      expect(result.height, 4);
      expect(identical(result.rgbBytes, src), isTrue);
    });

    test('90-degree quarter turn swaps width/height exactly', () {
      final src = flatImage(6, 4, 50, 60, 70);
      final result = applyCropTransform(
        src,
        6,
        4,
        const CropTransformParams(rotateQuarterTurns: 1),
      );
      expect(result.width, 4);
      expect(result.height, 6);
    });

    test('180-degree quarter turn preserves width/height', () {
      final src = flatImage(6, 4, 50, 60, 70);
      final result = applyCropTransform(
        src,
        6,
        4,
        const CropTransformParams(rotateQuarterTurns: 2),
      );
      expect(result.width, 6);
      expect(result.height, 4);
    });

    test('crop rect alone shrinks output to the expected size', () {
      final src = flatImage(100, 100, 1, 2, 3);
      final result = applyCropTransform(
        src,
        100,
        100,
        const CropTransformParams(
          cropLeft: 0.25,
          cropTop: 0.25,
          cropRight: 0.75,
          cropBottom: 0.75,
        ),
      );
      expect(result.width, 50);
      expect(result.height, 50);
    });

    test('crop of a flat-color image preserves that color throughout', () {
      final src = flatImage(40, 40, 200, 100, 50);
      final result = applyCropTransform(
        src,
        40,
        40,
        const CropTransformParams(
          cropLeft: 0.25,
          cropTop: 0.25,
          cropRight: 0.75,
          cropBottom: 0.75,
        ),
      );
      for (var p = 0; p < result.width * result.height; p++) {
        expect(result.rgbBytes[p * 3], closeTo(200, 1));
        expect(result.rgbBytes[p * 3 + 1], closeTo(100, 1));
        expect(result.rgbBytes[p * 3 + 2], closeTo(50, 1));
      }
    });

    test('straighten angle on a flat image preserves color (no crop)', () {
      final src = flatImage(50, 50, 120, 130, 140);
      final result = applyCropTransform(
        src,
        50,
        50,
        const CropTransformParams(straightenAngle: 5),
      );
      // Center pixel should sample well inside the original flat region.
      final centerIndex =
          ((result.height ~/ 2) * result.width + result.width ~/ 2) * 3;
      expect(result.rgbBytes[centerIndex], closeTo(120, 2));
      expect(result.rgbBytes[centerIndex + 1], closeTo(130, 2));
      expect(result.rgbBytes[centerIndex + 2], closeTo(140, 2));
    });
  });
}
