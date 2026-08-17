import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/luminance.dart';

void main() {
  group('luminanceRgb (Rec.709)', () {
    test('pure red (255,0,0) yields 0.2126 * 255', () {
      final l = luminanceRgb(255, 0, 0);
      expect(l, closeTo(0.2126 * 255, 0.01));
    });

    test('pure green (0,255,0) yields 0.7152 * 255', () {
      final l = luminanceRgb(0, 255, 0);
      expect(l, closeTo(0.7152 * 255, 0.01));
    });

    test('pure blue (0,0,255) yields 0.0722 * 255', () {
      final l = luminanceRgb(0, 0, 255);
      expect(l, closeTo(0.0722 * 255, 0.01));
    });

    test('white (255,255,255) yields 255', () {
      final l = luminanceRgb(255, 255, 255);
      expect(l, closeTo(255, 0.01));
    });

    test('black (0,0,0) yields 0', () {
      final l = luminanceRgb(0, 0, 0);
      expect(l, closeTo(0, 0.01));
    });

    test('mid-gray (128,128,128) yields ~128', () {
      final l = luminanceRgb(128, 128, 128);
      expect(l, closeTo(128, 0.5));
    });
  });

  group('extractLuminance', () {
    test('extracts Rec.709 luminance from packed RGB buffer', () {
      final rgb = Float32List.fromList([
        255, 0, 0, // red
        0, 255, 0, // green
        0, 0, 255, // blue
        128, 128, 128, // mid-gray
      ]);
      final out = Float32List(4);
      extractLuminance(rgb, out);
      expect(out[0], closeTo(luminanceRgb(255, 0, 0), 0.01));
      expect(out[1], closeTo(luminanceRgb(0, 255, 0), 0.01));
      expect(out[2], closeTo(luminanceRgb(0, 0, 255), 0.01));
      expect(out[3], closeTo(luminanceRgb(128, 128, 128), 0.01));
    });
  });

  group('applyLuminanceDelta', () {
    test('adds delta equally to all channels, preserving chroma', () {
      final rgb = Float32List.fromList([
        100, 80, 60, // chromatic pixel
        200, 200, 200, // neutral pixel
      ]);
      final delta = Float32List.fromList([10.0, -5.0]);
      applyLuminanceDelta(rgb, delta);

      // First pixel: all channels shifted by +10
      expect(rgb[0], closeTo(110, 0.01));
      expect(rgb[1], closeTo(90, 0.01));
      expect(rgb[2], closeTo(70, 0.01));

      // Second pixel: all channels shifted by -5
      expect(rgb[3], closeTo(195, 0.01));
      expect(rgb[4], closeTo(195, 0.01));
      expect(rgb[5], closeTo(195, 0.01));

      // Chroma (differences) preserved
      expect(rgb[0] - rgb[1], closeTo(20, 0.01));
      expect(rgb[3] - rgb[4], closeTo(0, 0.01));
    });
  });
}
