import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/editor_screen.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// Denoise smooths detail away; Sharpen is what brings it back. This pins
/// that pairing, because calibration can break it silently and the only
/// symptom is a photograph that starts looking like a painting.
///
/// It is deliberately a behavioural check and not a structural one. The
/// obvious structural rule — "never damp a detail control more than the
/// smoothing it answers to" — is measurably wrong: Texture damped to 0.3
/// restores more than Sharpen does undamped, and undamping it overshoots
/// the undenoised frame by a factor. So the thing worth asserting is the
/// outcome, not the arithmetic that produces it.
void main() {
  const w = 300, h = 220;

  /// Mean absolute Laplacian: how much fine detail a frame carries.
  double detail(Uint8List rgb) {
    var sum = 0.0;
    var n = 0;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        sum +=
            (4 * rgb[(y * w + x) * 3] -
                    rgb[((y - 1) * w + x) * 3] -
                    rgb[((y + 1) * w + x) * 3] -
                    rgb[(y * w + x - 1) * 3] -
                    rgb[(y * w + x + 1) * 3])
                .abs();
        n++;
      }
    }
    return sum / n;
  }

  /// Texture at several scales plus sensor-like noise — something for
  /// denoise to remove and for sharpening to find again.
  Uint8List source() {
    final rnd = math.Random(11);
    final rgb = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final base =
            110 +
            40 * math.sin(x / 3.0) * math.cos(y / 4.0) +
            25 * math.sin((x + y) / 11.0) +
            rnd.nextInt(14);
        final v = base.clamp(0, 255).toInt();
        final i = (y * w + x) * 3;
        rgb[i] = v;
        rgb[i + 1] = (v * 0.96).round();
        rgb[i + 2] = (v * 0.90).round();
      }
    }
    return rgb;
  }

  final src = source();

  /// Rendered through the real calibration, at the scale a preview runs
  /// at rather than this buffer's own.
  ///
  /// That distinction is not cosmetic. renderScale is longEdge/1024, so
  /// on a 300px buffer the sharpen radius would fall to 0.29, the blur
  /// behind the unsharp mask would be a no-op, and Sharpen would appear
  /// to do nothing at any setting — a false alarm this test was written
  /// after chasing.
  double rendered(Map<String, double> sliders) {
    final params = RenderParams.fromValues(
      withGlobalEditAmountApplied({'GlobalEditAmount': 100.0, ...sliders}),
      baseContrast: 0,
    ).withRenderScaleFor(1024, 768);
    return detail(renderRgb(w, h, src, params));
  }

  test('sharpening recovers what denoise takes', () {
    final plain = rendered(const {});
    final denoised = rendered(const {'AiDenoiseLevel': 2});
    final sharpened = rendered(const {
      'AiDenoiseLevel': 2,
      'SharpenAmount': 60,
    });

    expect(
      denoised,
      lessThan(plain),
      reason: 'denoise that removes no detail is not denoising',
    );

    final removed = plain - denoised;
    final recovered = (sharpened - denoised) / removed;
    expect(
      recovered,
      greaterThan(0.4),
      reason:
          'a Sharpen of 60 recovers only ${(recovered * 100).round()}% of '
          'the detail denoise removed. The AI denoise amounts are not '
          'damped by the Amount slider at all, so damping the controls '
          'that answer them tips the balance into smoothing — which is '
          'what a painterly render is. Measured at 51% when this was '
          'written and 25% with SharpenAmount damped to 0.5, which is the '
          'regression this exists to catch.',
    );
  });

  test('Texture is not starved either', () {
    final denoised = rendered(const {'AiDenoiseLevel': 2});
    final textured = rendered(const {'AiDenoiseLevel': 2, 'Texture': 60});
    expect(
      textured,
      greaterThan(denoised),
      reason: 'Texture is the other control that answers denoise',
    );
  });
}
