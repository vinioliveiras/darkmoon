import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/ai_denoise.dart';
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
// Grain and Vignette normalise against a 1080px reference. Texture,
// Clarity, Dehaze and the tonal blur scale with the frame instead, so a
// sigma-35 Clarity covers the same 3.4% of the scene at every resolution.
//
// Sharpen, AI Denoise and the always-on baseline chroma smoothing sit in
// neither camp: they are capped at calDetailRadiusMaxScale, because noise
// and sharpening reach a fixed number of real pixels rather than a fixed
// fraction of the scene. Uncapped, a 24MP export ran them at 5.9x their
// tuned radii and photographs came out looking like oil paintings; see
// that constant, and detail_scale_invariance_test.dart for the guard.
//
// Measured 2026-09-03 at a 4x linear ratio (mean absolute byte difference
// after area-averaging the large render down to the small one):
//
//                          before  after   (after = the three pixel-domain
//                                           stages capped, 2026-09-08)
//   neutral                1.15    1.08    default sharpen + chroma smoothing
//   exposure +20           1.17    1.10    control: a pure point op, flat
//   dehaze 60              1.87    1.13
//   sharpen 100            1.91    1.18
//   clarity 60             3.37    1.30
//   texture 60             3.84    1.29
//   grain 60               6.92    6.90    expected: noise, a different
//                                          pattern by construction, not a
//                                          resolution bug
//
// Only Sharpen was capped of those, yet Clarity fell 3.37 -> 1.30 and
// Texture 3.84 -> 1.29 without being touched. The always-on chroma
// smoothing runs underneath every one of these renders, so most of what
// each row appeared to measure was actually that one stage drifting with
// resolution — it was the largest single source of preview-to-export
// divergence in the renderer, larger than Clarity, Texture and Dehaze
// together, and it has no slider to turn it off.
//
// Left as a characterisation test rather than a failing one for the
// stages that still scale: normalising their sigmas changes the look of
// every existing edit and preset, so it is a product decision, not a bug
// fix to slip in. The control case is asserted so this test still fails
// if a *point* op ever picks up a resolution dependency.
void main() {
  const smallW = 512, smallH = 384;
  const bigW = 2048, bigH = 1536; // 4x linear, the preview -> export ratio

  double compare(String label, RenderParams params) {
    // withRenderScaleFor is what the real entry points apply once crop and
    // lens geometry have settled the frame size (render_job.dart,
    // export_job.dart) — without it this would measure params that never
    // reach the pipeline.
    final small = renderRgb(
      smallW,
      smallH,
      scene(smallW, smallH),
      params.withRenderScaleFor(smallW, smallH),
    );
    final big = renderRgb(
      bigW,
      bigH,
      scene(bigW, bigH),
      params.withRenderScaleFor(bigW, bigH),
    );
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

  // The companion guard to the measurements above: they show *how much* a
  // stage depends on resolution, but they cannot show that a stage is
  // wired to renderScale at all — a wide blur on a test-sized frame is
  // already near-global, so doubling its sigma changes almost nothing.
  // (Verified: deliberately dropping the scale from Dehaze is invisible to
  // an end-to-end pixel comparison at 96px, 120px and 480px alike.)
  //
  // So this asserts the one thing that is unambiguous — each scaled stage
  // must *respond* to renderScale — on a frame comfortably larger than the
  // radii involved.
  group('every scaled stage responds to renderScale', () {
    const w = 768, h = 512;
    final photo = scene(w, h);

    void expectResponds(
      String label,
      RenderParams base, {
      double minResponse = 1.0,
    }) {
      test(label, () {
        final atOne = renderRgb(
          w,
          h,
          photo,
          base.withRenderScaleFor(1024, 683),
        );
        final atThree = renderRgb(
          w,
          h,
          photo,
          base.withRenderScaleFor(3072, 2048),
        );
        var sum = 0.0;
        for (var i = 0; i < atOne.length; i++) {
          sum += (atOne[i] - atThree[i]).abs();
        }
        final mean = sum / atOne.length;
        // ignore: avoid_print
        print(
          '[responds] ${label.padRight(20)} mean=${mean.toStringAsFixed(2)}',
        );
        expect(
          mean,
          greaterThan(minResponse),
          reason:
              '$label barely changed between renderScale 1 and 3 — its '
              'radius is probably not multiplied by renderScale at all',
        );
      });
    }

    expectResponds('texture', const RenderParams(baseContrast: 0, texture: 70));
    expectResponds('clarity', const RenderParams(baseContrast: 0, clarity: 70));
    expectResponds('dehaze', const RenderParams(baseContrast: 0, dehaze: 70));
    expectResponds(
      'shadows (tonal blur)',
      const RenderParams(baseContrast: 0, shadows: 60),
      // The tonal blur only feeds _applyRapidShadowsBlacks' detail term,
      // whose detailRatio is clamped to [0.8, 1.25] by construction — so
      // however far its sigma moves, its influence on the output is
      // bounded. It responds, just not as loudly as the stages whose blur
      // *is* the effect.
      //
      // Was 0.70 against a 0.4 floor until 2026-09-08. Most of that was
      // never the tonal blur: the always-on chroma smoothing runs in every
      // one of these renders and used to scale too, so it moved between
      // scale 1 and 3 in the shadows case exactly as it did in all the
      // others. Capping it left this stage's own response, 0.19.
      minResponse: 0.1,
    );
  });

  // The inverse guard, for the three stages that must *stop* responding.
  // detail_scale_invariance_test.dart asserts the same property on the
  // rendered pixels; this one keeps it next to the stages it is the
  // exception to, so a future "wire everything to renderScale" sweep has
  // to read why these three are not in that list.
  group('pixel-domain stages ignore renderScale', () {
    const w = 768, h = 512;
    final photo = scene(w, h);

    void expectFlat(String label, RenderParams base) {
      test(label, () {
        final atOne = renderRgb(w, h, photo, base.withRenderScaleFor(1024, 683));
        final atThree = renderRgb(
          w,
          h,
          photo,
          base.withRenderScaleFor(3072, 2048),
        );
        var worst = 0;
        for (var i = 0; i < atOne.length; i++) {
          final d = (atOne[i] - atThree[i]).abs();
          if (d > worst) worst = d;
        }
        expect(
          worst,
          0,
          reason:
              '$label changed between renderScale 1 and 3. Its radius is in '
              'real pixels and must not follow the frame — see '
              'calDetailRadiusMaxScale.',
        );
      });
    }

    expectFlat(
      'sharpen',
      const RenderParams(
        baseContrast: 0,
        sharpen: SharpenParams(amount: 100, radius: 3),
      ),
    );
    expectFlat(
      'ai denoise',
      const RenderParams(
        baseContrast: 0,
        aiDenoise: AiDenoiseParams(level: AiDenoiseLevel.strong),
      ),
    );
    // Always on, no slider — the one of the three a user cannot turn off.
    expectFlat('baseline chroma smoothing', const RenderParams(baseContrast: 0));
  });
}
