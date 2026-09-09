import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/blur.dart';
import 'package:flutter_test/flutter_test.dart';

/// Box-average down by [f], then bilinear back up — the same two passes
/// downsample_box.frag and upsample.frag already do on the GPU.
Float32List _down(Float32List src, int w, int h, int f, int sw, int sh) {
  final out = Float32List(sw * sh);
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      var sum = 0.0;
      var n = 0;
      for (var dy = 0; dy < f; dy++) {
        for (var dx = 0; dx < f; dx++) {
          final sx = x * f + dx, sy = y * f + dy;
          if (sx < w && sy < h) {
            sum += src[sy * w + sx];
            n++;
          }
        }
      }
      out[y * sw + x] = n == 0 ? 0 : sum / n;
    }
  }
  return out;
}

Float32List _up(Float32List src, int sw, int sh, int w, int h) {
  final out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final fy = ((y + 0.5) * sh / h - 0.5).clamp(0.0, sh - 1.0);
    final y0 = fy.floor(), y1 = math.min(y0 + 1, sh - 1);
    final ty = fy - y0;
    for (var x = 0; x < w; x++) {
      final fx = ((x + 0.5) * sw / w - 0.5).clamp(0.0, sw - 1.0);
      final x0 = fx.floor(), x1 = math.min(x0 + 1, sw - 1);
      final tx = fx - x0;
      final a = src[y0 * sw + x0] * (1 - tx) + src[y0 * sw + x1] * tx;
      final b = src[y1 * sw + x0] * (1 - tx) + src[y1 * sw + x1] * tx;
      out[y * w + x] = a * (1 - ty) + b * ty;
    }
  }
  return out;
}

void main() {
  test('blurring small and scaling up matches blurring big', () {
    const w = 900, h = 600;
    final rnd = math.Random(3);
    final src = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        // Structure at several scales plus noise — the fine detail is what
        // a reduced-resolution blur could plausibly get wrong.
        src[y * w + x] = (128 +
                80 * math.sin(x / 40.0) * math.cos(y / 55.0) +
                40 * math.sin((x + y) / 9.0) +
                rnd.nextInt(30))
            .clamp(0, 255);
      }
    }

    for (final sigma in [40.0, 120.0, 300.0]) {
      final direct = gaussianBlurChannel(src, w, h, sigma);
      for (final f in [2, 4, 8]) {
        final sw = (w / f).ceil(), sh = (h / f).ceil();
        final small = _down(src, w, h, f, sw, sh);
        final blurred = gaussianBlurChannel(small, sw, sh, sigma / f);
        final back = _up(blurred, sw, sh, w, h);
        var sum = 0.0, worst = 0.0;
        for (var i = 0; i < w * h; i++) {
          final d = (direct[i] - back[i]).abs();
          sum += d;
          if (d > worst) worst = d;
        }
        // ignore: avoid_print
        print('sigma ${sigma.toStringAsFixed(0).padLeft(3)}  /$f  '
            'mean ${(sum / (w * h)).toStringAsFixed(3).padLeft(6)}  '
            'max ${worst.toStringAsFixed(2).padLeft(6)}  (0-255)');
      }
    }
  });
}
