import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/editor_screen.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:flutter_test/flutter_test.dart';

/// Denoise and Sharpen reach a fixed number of real pixels. Clarity and
/// Dehaze reach a fixed fraction of the scene. `calRadiusReferenceLongEdge`
/// scaled all of them with the frame, which meant a 24MP export ran the
/// denoise at sigma 11.7px and the sharpen at 5.9px — a large-radius
/// edge-preserving blur under a large-radius unsharp mask, which is the
/// recipe for an oil painting, and it is what photographs came out looking
/// like. `calDetailRadiusMaxScale` caps the three pixel-domain stages.
///
/// The 1024px preview renders at scale 1.0, so it can never show this
/// regression. That is exactly why it needs a test: the only place it was
/// ever visible was the exported file.
void main() {
  const w = 256, h = 256;

  /// Fine texture, mid detail and a hard edge, plus sensor-like noise.
  Uint8List source() {
    final rnd = math.Random(7);
    final rgb = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var v = 128.0;
        v += 10 * math.sin(x / 0.8) * math.sin(y / 0.9);
        v += 14 * math.sin(x / 2.5) * math.cos(y / 2.2);
        v += 20 * math.sin((x + y) / 9.0);
        v += x > 128 ? 45 : -45;
        v += (rnd.nextDouble() - 0.5) * 12;
        final c = v.clamp(0.0, 255.0).toInt();
        final i = (y * w + x) * 3;
        rgb[i] = c;
        rgb[i + 1] = c;
        rgb[i + 2] = c;
      }
    }
    return rgb;
  }

  final src = source();

  /// The same buffer rendered as if it were a frame [longEdge] px wide.
  /// Only the declared frame size changes, so anything that differs
  /// between two calls is a stage reading the frame size when it should
  /// be reading pixels.
  Uint8List renderAsFrame(Map<String, double> sliders, int longEdge) {
    final params = RenderParams.fromValues(
      withGlobalEditAmountApplied({'GlobalEditAmount': 100.0, ...sliders}),
      baseContrast: 0,
    ).withRenderScaleFor(longEdge, (longEdge * 2 / 3).round());
    return renderRgb(w, h, src, params);
  }

  /// Every stage except denoise and sharpen is at its neutral value here,
  /// so the two renders must agree pixel for pixel.
  for (final level in [1.0, 2.0, 3.0]) {
    for (final sharpen in [0.0, 40.0, 100.0]) {
      test(
        'denoise $level + sharpen $sharpen renders the same at 1024 and 6000',
        () {
          final sliders = {
            'AiDenoiseLevel': level,
            'SharpenAmount': sharpen,
          };
          final preview = renderAsFrame(sliders, 1024);
          final export = renderAsFrame(sliders, 6000);
          var worst = 0;
          for (var i = 0; i < preview.length; i++) {
            final d = (preview[i] - export[i]).abs();
            if (d > worst) worst = d;
          }
          expect(
            worst,
            0,
            reason:
                'A pixel-domain stage is scaling its radius with the frame. '
                'Worst channel difference $worst/255 between a 1024px and a '
                '6000px frame of identical content. See '
                'calDetailRadiusMaxScale.',
          );
        },
      );
    }
  }
}
