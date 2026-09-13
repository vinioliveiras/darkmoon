import 'dart:math' as math;
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

    test('selective clarity only reaches its own tonal band', () {
      // A textured dark patch (luma ~40) and a textured bright one (~215).
      Float32List patch(int base) {
        final img = Float32List(8 * 8 * 3);
        for (var p = 0; p < 64; p++) {
          final v = (base + ((p % 8 + p ~/ 8) % 2 == 0 ? 12 : -12)).toDouble();
          img[p * 3] = v;
          img[p * 3 + 1] = v;
          img[p * 3 + 2] = v;
        }
        return img;
      }

      final darkRef = patch(40), brightRef = patch(215);
      final dark = patch(40), bright = patch(215);
      const shadowsOnly = TonalAmounts(shadows: 80);
      applyLocalContrast(dark, 8, 8, 0, 2, tonal: shadowsOnly);
      applyLocalContrast(bright, 8, 8, 0, 2, tonal: shadowsOnly);
      double change(Float32List a, Float32List b) {
        var s = 0.0;
        for (var i = 0; i < a.length; i++) {
          s += (a[i] - b[i]).abs();
        }
        return s / a.length;
      }

      expect(change(dark, darkRef), greaterThan(1.0));
      expect(change(bright, brightRef), lessThan(1e-6));
      final (ws, wm, wh) = tonalBandWeights(0.3);
      expect(ws + wm + wh, closeTo(1.0, 1e-9));
      expect(ws, greaterThan(wh));
      expect(tonalBandWeights(0.9).$3, 1.0);
    });

    test('the guided base halos a step edge far less than the Gaussian', () {
      // 60 | 200 step; Clarity at 100 (amount 65 after calClarityStrength)
      // with the Gaussian base overshoots by ~19 levels either side, the
      // guided base by ~4 (2026-09-10).
      const w = 320, h = 8;
      Float32List step() {
        final img = Float32List(w * h * 3);
        for (var p = 0; p < w * h; p++) {
          final v = p % w < 160 ? 60.0 : 200.0;
          img[p * 3] = v;
          img[p * 3 + 1] = v;
          img[p * 3 + 2] = v;
        }
        return img;
      }

      double overshoot(Float32List img) {
        var over = 0.0;
        for (var x = 0; x < w; x++) {
          final v = img[(4 * w + x) * 3];
          over = math.max(over, math.max(v - 200, 60 - v));
        }
        return over;
      }

      final gaussian = step();
      applyLocalContrast(gaussian, w, h, 65, 25, protectMidtones: true);
      final guided = step();
      applyLocalContrast(
        guided,
        w,
        h,
        65,
        25,
        protectMidtones: true,
        edgeThreshold: 20,
      );
      expect(overshoot(gaussian), greaterThan(15));
      expect(overshoot(guided), lessThan(6));
    });

    test('the guided base still boosts texture under the threshold', () {
      // A ±20 sinusoid (period 20 px) gains ~1.5x at Clarity 100 (amount
      // 65) with either base: 1.55 Gaussian, 1.51 guided.
      const w = 320, h = 8;
      Float32List texture() {
        final img = Float32List(w * h * 3);
        for (var p = 0; p < w * h; p++) {
          final v = 128 + 20 * math.sin(2 * math.pi * (p % w) / 20);
          img[p * 3] = v;
          img[p * 3 + 1] = v;
          img[p * 3 + 2] = v;
        }
        return img;
      }

      double swing(Float32List img) {
        var lo = 255.0, hi = 0.0;
        for (var x = 40; x < w - 40; x++) {
          final v = img[(4 * w + x) * 3];
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
        return (hi - lo) / 40;
      }

      final guided = texture();
      applyLocalContrast(
        guided,
        w,
        h,
        65,
        25,
        protectMidtones: true,
        edgeThreshold: 20,
      );
      expect(swing(guided), closeTo(1.5, 0.1));
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
