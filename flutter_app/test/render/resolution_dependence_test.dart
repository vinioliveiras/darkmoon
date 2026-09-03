import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/grain.dart';
import 'package:darkmoon/render/sharpen.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same scene at any pixel size: features are placed in normalized
/// coordinates, so a 512px and a 2048px render show the identical picture
/// at different sampling densities — exactly the relationship between the
/// editing preview, the full-quality preview and the export.
Uint8List scene(int w, int h) {
  final out = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final nx = x / w, ny = y / h;
      // A broad gradient, mid-frequency bars, and a hard edge.
      var v = 90 + 90 * math.sin(nx * math.pi * 3) * math.cos(ny * math.pi * 2);
      v += 30 * math.sin(nx * math.pi * 24);
      if (nx > 0.5) v += 40;
      final i = (y * w + x) * 3;
      final b = v.clamp(0.0, 255.0).round();
      out[i] = b;
      out[i + 1] = (b * 0.92).round();
      out[i + 2] = (b * 0.85).round();
    }
  }
  return out;
}

/// Area-average downscale, so the big render is compared on the small
/// render's own terms rather than on sampling differences.
Uint8List downscale(Uint8List src, int sw, int sh, int dw, int dh) {
  final out = Uint8List(dw * dh * 3);
  final fx = sw ~/ dw, fy = sh ~/ dh;
  for (var y = 0; y < dh; y++) {
    for (var x = 0; x < dw; x++) {
      var r = 0, g = 0, b = 0;
      for (var oy = 0; oy < fy; oy++) {
        for (var ox = 0; ox < fx; ox++) {
          final i = (((y * fy + oy) * sw) + (x * fx + ox)) * 3;
          r += src[i];
          g += src[i + 1];
          b += src[i + 2];
        }
      }
      final n = fx * fy;
      final i = (y * dw + x) * 3;
      out[i] = r ~/ n;
      out[i + 1] = g ~/ n;
      out[i + 2] = b ~/ n;
    }
  }
  return out;
}

// Characterises how much each stage's result depends on the pixel size it
// is rendered at — which is not an abstract concern here: the same edit is
// rendered at three different resolutions (the editing preview, the
// dynamic full-quality preview, and the export), so any stage that is
// resolution-dependent looks different in all three.
//
// Grain and Vignette already normalise against a 1080px reference.
// Sharpen, Texture, Clarity, Dehaze and the always-on baseline chroma
// smoothing do not: their radii and sigmas are absolute pixel counts, so a
// sigma-35 Clarity spans 3.4% of a 1024px frame and 0.45% of a 7728px one.
//
// Measured 2026-09-03 at a 4x linear ratio (mean absolute byte difference
// after area-averaging the large render down to the small one):
//
//   neutral                1.15   (default sharpen + chroma smoothing)
//   exposure +20           1.17   control: a pure point op, flat
//   dehaze 60              1.87
//   sharpen 100            1.91
//   clarity 60             3.37
//   texture 60             3.84
//   grain 60               6.92   expected: noise, a different pattern by
//                                 construction, not a resolution bug
//
// Left as a characterisation test rather than a failing one: normalising
// those sigmas changes the look of every existing edit and preset, so it
// is a product decision, not a bug fix to slip in. The control case is
// asserted so this test still fails if a *point* op ever picks up a
// resolution dependency.
void main() {
  const smallW = 512, smallH = 384;
  const bigW = 2048, bigH = 1536; // 4x linear, the preview -> export ratio

  double compare(String label, RenderParams params) {
    final small = renderRgb(smallW, smallH, scene(smallW, smallH), params);
    final big = renderRgb(bigW, bigH, scene(bigW, bigH), params);
    final bigDown = downscale(big, bigW, bigH, smallW, smallH);
    var sum = 0.0;
    var max = 0;
    for (var i = 0; i < small.length; i++) {
      final d = (small[i] - bigDown[i]).abs();
      sum += d;
      if (d > max) max = d;
    }
    final mean = sum / small.length;
    // ignore: avoid_print
    print(
      '[res] ${label.padRight(26)} mean=${mean.toStringAsFixed(2)} max=$max',
    );
    return mean;
  }

  test('same params, 4x resolution difference', () {
    final neutral = compare('neutral', const RenderParams(baseContrast: 0));
    final exposure = compare(
      'exposure +20',
      const RenderParams(baseContrast: 0, exposure: 20),
    );
    // Exposure is a pure per-pixel multiply, so it must add nothing on top
    // of whatever the neutral pipeline already costs. If this ever drifts,
    // a point op has picked up a neighbourhood dependency.
    expect(
      exposure - neutral,
      lessThan(0.2),
      reason:
          'a point op must not become resolution-dependent '
          '(neutral $neutral, exposure $exposure)',
    );
    compare('clarity 60', const RenderParams(baseContrast: 0, clarity: 60));
    compare('texture 60', const RenderParams(baseContrast: 0, texture: 60));
    compare('dehaze 60', const RenderParams(baseContrast: 0, dehaze: 60));
    compare(
      'sharpen 100',
      const RenderParams(
        baseContrast: 0,
        sharpen: SharpenParams(amount: 100, radius: 2),
      ),
    );
    compare(
      'grain 60 (normalised)',
      const RenderParams(baseContrast: 0, grain: GrainParams(amount: 60)),
    );
  });
}
