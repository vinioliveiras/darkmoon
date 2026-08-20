import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/sharpen.dart';

void main() {
  group('applySharpen', () {
    test('neutral sharpen on flat gray does not shift chroma', () {
      final img = Float32List(8 * 8 * 3);
      for (var i = 0; i < img.length; i++) {
        img[i] = 128.0;
      }

      applySharpen(
        img,
        8,
        8,
        SharpenParams(amount: 50, radius: 1.5, detail: 25, masking: 25),
      );

      for (var p = 0; p < 64; p++) {
        final i = p * 3;
        expect(img[i] - img[i + 1], closeTo(0, 0.5));
        expect(img[i + 1] - img[i + 2], closeTo(0, 0.5));
      }
    });

    test('sharpen on chromatic flat patch preserves chroma', () {
      final img = Float32List(8 * 8 * 3);
      for (var p = 0; p < 64; p++) {
        final i = p * 3;
        img[i] = 150.0;
        img[i + 1] = 100.0;
        img[i + 2] = 80.0;
      }

      applySharpen(
        img,
        8,
        8,
        SharpenParams(amount: 50, radius: 1.5, detail: 25, masking: 25),
      );

      for (var p = 0; p < 64; p++) {
        final i = p * 3;
        expect(img[i] - img[i + 1], closeTo(50, 1.0));
        expect(img[i + 1] - img[i + 2], closeTo(20, 1.0));
      }
    });

    test('amount 0 is a no-op', () {
      final img = Float32List.fromList([100, 120, 140, 80, 90, 110]);
      final copy = Float32List.fromList(img);
      applySharpen(img, 1, 2, SharpenParams(amount: 0));
      for (var i = 0; i < img.length; i++) {
        expect(img[i], closeTo(copy[i], 0.01));
      }
    });
  });
}
