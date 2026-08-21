// Phase 6 of the GPU render-pipeline plan: verifies the fully assembled
// renderRgbGpu (Phases 1-5's stages, in render.dart's exact order) matches
// the serial CPU renderRgb — the first test exercising every stage
// together in one call, rather than each phase's own isolated primitive.
//
// Run with: flutter test integration_test/gpu_full_pipeline_test.dart -d windows
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/ai_denoise.dart';
import 'package:darkmoon/render/color_grading.dart';
import 'package:darkmoon/render/color_mixer.dart';
import 'package:darkmoon/render/gpu/render_gpu.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/sharpen.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:darkmoon/render/vignette.dart';

/// A hazier, more richly detailed synthetic photo than the earlier
/// per-stage tests — real edges, a luminance gradient, and enough size for
/// Clarity's sigma=25 blur and Dehaze's dark-channel window to have real
/// spatial structure to work with, since this test exercises every stage
/// at once rather than one primitive in isolation.
Uint8List _syntheticPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final edge = ((x ~/ 8) + (y ~/ 6)) % 2 == 0 ? 22 : 0;
      final haze = ((x + y) * 40) ~/ (width + height);
      bytes[i] = ((x * 150) ~/ width + edge + 30 + haze).clamp(0, 255);
      bytes[i + 1] = ((y * 150) ~/ height + edge + 45 + haze).clamp(0, 255);
      bytes[i + 2] = (((x + y) * 150) ~/ (width + height) + edge + 60 + haze)
          .clamp(0, 255);
    }
  }
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 120;
  const height = 90;
  final photo = _syntheticPhoto(width, height);

  Future<void> expectMatchesCpu(
    RenderParams params,
    String label, {
    int maxTolerance = 32,
  }) async {
    final cpu = renderRgb(width, height, photo, params);
    final gpu = await renderRgbGpu(width, height, photo, params);
    expect(gpu.length, cpu.length, reason: '$label: byte length mismatch');

    var sumDiff = 0.0;
    var maxDiff = 0;
    for (var i = 0; i < cpu.length; i++) {
      final d = (cpu[i] - gpu[i]).abs();
      sumDiff += d;
      if (d > maxDiff) maxDiff = d;
    }
    final meanDiff = sumDiff / cpu.length;
    // ignore: avoid_print
    print('[gpu_full_pipeline] $label: mean=$meanDiff max=$maxDiff');
    // Widest tolerance of any test file: every stage's own quantization
    // compounds across the full ~25-pass chain (point ops x2, chroma
    // smoothing ~10 passes, AI denoise ~20 passes, sharpen ~10 passes,
    // texture+clarity ~14 passes, dehaze ~8 passes, post-dehaze), plus one
    // CPU<->GPU readback for Dehaze's atmospheric-light estimate.
    expect(
      meanDiff,
      lessThan(6.0),
      reason:
          '$label: mean diff $meanDiff — likely a real bug, not just '
          'accumulated GPU/CPU rounding noise',
    );
    expect(
      maxDiff,
      lessThan(maxTolerance),
      reason: '$label: max diff $maxDiff',
    );
  }

  group('renderRgbGpu (full pipeline) matches renderRgb', () {
    testWidgets('neutral (default) params', (tester) async {
      await expectMatchesCpu(const RenderParams(), 'neutral');
    });

    testWidgets('every stage active at once', (tester) async {
      await expectMatchesCpu(
        RenderParams(
          temperature: 6800,
          tint: 12,
          exposure: 20,
          brightness: 5,
          contrast: 15,
          highlights: -25,
          shadows: 30,
          whites: 10,
          blacks: -10,
          texture: 40,
          clarity: 35,
          dehaze: 45,
          vibrance: 25,
          saturation: 10,
          curves: PhotoCurves(
            tone: const [
              CurvePoint(0, 0),
              CurvePoint(0.5, 0.6),
              CurvePoint(1, 1),
            ],
          ),
          colorMixer: const ColorMixerValues(
            red: ChannelAdjust(hue: 10, saturation: 15, luminance: -5),
          ),
          colorGrading: const ColorGradingValues(
            shadows: GradeRange(hue: 210, saturation: 20),
          ),
          sharpen: const SharpenParams(
            amount: 70,
            radius: 1.2,
            detail: 40,
            masking: 30,
          ),
          vignette: const VignetteParams(
            amount: -35,
            midpoint: 45,
            feather: 60,
          ),
        ),
        'everything active',
        // This case's active Exposure (20) drives real highlight headroom
        // past 255; GPU's 8-bit intermediate render targets clip that
        // permanently right after the exposure pass, while CPU's single-
        // clamp-at-the-end Float32 pipeline carries the true overexposed
        // value through several more stages first — a real, expected
        // architectural quirk (root-caused and documented in
        // gpu_point_ops_test.dart's own exposure case), not a shader bug.
        // Mean diff here stays low (~2.7/255); only a handful of clip-
        // boundary pixels push max diff slightly past the file's default.
        maxTolerance: 40,
      );
    });

    testWidgets('haze addition (negative Dehaze) combined with tone edits', (
      tester,
    ) async {
      await expectMatchesCpu(
        const RenderParams(
          exposure: -15,
          contrast: 20,
          dehaze: -40,
          saturation: -20,
        ),
        'negative dehaze + tone',
      );
    });

    testWidgets('AI denoise active alongside sharpen/clarity', (tester) async {
      await expectMatchesCpu(
        RenderParams(
          aiDenoise: const AiDenoiseParams(level: AiDenoiseLevel.medium),
          sharpen: const SharpenParams(amount: 60, masking: 40),
          clarity: 30,
        ),
        'ai denoise + sharpen + clarity',
      );
    });
  });
}
