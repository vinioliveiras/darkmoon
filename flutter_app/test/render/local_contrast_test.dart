import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/local_contrast.dart';

void main() {
  group('applyLocalContrast (Texture/Clarity)', () {
    test('neutral texture on flat gray does not shift chroma', () {
      // 4x4 flat neutral gray (128,128,128)
      final img = Float32List(4 * 4 * 3);
      for (var i = 0; i < img.length; i++) {
        img[i] = 128.0;
      }

      applyLocalContrast(img, 4, 4, 50, 3, noiseAware: true);

      // All pixels should remain nearly neutral
      for (var p = 0; p < 16; p++) {
        final i = p * 3;
        expect(img[i] - img[i + 1], closeTo(0, 0.5));
        expect(img[i + 1] - img[i + 2], closeTo(0, 0.5));
        expect(img[i] - img[i + 2], closeTo(0, 0.5));
      }
    });

    test('neutral texture on chromatic flat patch does not shift chroma', () {
      // 4x4 flat chromatic patch (R=150, G=100, B=80)
      final img = Float32List(4 * 4 * 3);
      for (var p = 0; p < 16; p++) {
        final i = p * 3;
        img[i] = 150.0;
        img[i + 1] = 100.0;
        img[i + 2] = 80.0;
      }

      applyLocalContrast(img, 4, 4, 50, 3, noiseAware: true);

      // Chroma differences should be preserved
      for (var p = 0; p < 16; p++) {
        final i = p * 3;
        expect(img[i] - img[i + 1], closeTo(50, 1.0));
        expect(img[i + 1] - img[i + 2], closeTo(20, 1.0));
      }
    });

    test('clarity on flat neutral does not shift chroma', () {
      final img = Float32List(8 * 8 * 3);
      for (var i = 0; i < img.length; i++) {
        img[i] = 100.0;
      }

      applyLocalContrast(img, 8, 8, 50, 25, protectMidtones: true);

      for (var p = 0; p < 64; p++) {
        final i = p * 3;
        expect(img[i] - img[i + 1], closeTo(0, 0.5));
        expect(img[i + 1] - img[i + 2], closeTo(0, 0.5));
      }
    });

    test('amount 0 is a no-op', () {
      final img = Float32List.fromList([100, 120, 140, 80, 90, 110]);
      final copy = Float32List.fromList(img);
      applyLocalContrast(img, 1, 2, 0, 3, noiseAware: true);
      for (var i = 0; i < img.length; i++) {
        expect(img[i], closeTo(copy[i], 0.01));
      }
    });
  });
}
