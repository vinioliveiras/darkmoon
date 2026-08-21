// Phase 7 of the GPU render-pipeline plan: verifies renderRgbWithMasksGpu
// matches render.dart's renderRgbWithMasks CPU reference — the global layer
// plus each mask type's own stacked, alpha-blended re-render.
//
// Run with: flutter test integration_test/gpu_mask_test.dart -d windows
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/gpu/mask_gpu.dart';
import 'package:darkmoon/render/mask.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

Uint8List _syntheticPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final edge = ((x ~/ 8) + (y ~/ 6)) % 2 == 0 ? 20 : 0;
      bytes[i] = ((x * 180) ~/ width + edge + 20).clamp(0, 255);
      bytes[i + 1] = ((y * 180) ~/ height + edge + 40).clamp(0, 255);
      bytes[i + 2] = (((x + y) * 180) ~/ (width + height) + edge + 60).clamp(
        0,
        255,
      );
    }
  }
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 100;
  const height = 76;
  final photo = _syntheticPhoto(width, height);

  Future<void> expectMatchesCpu(
    RenderParams globalParams,
    List<MaskLayer> masks,
    String label,
  ) async {
    final cpu = renderRgbWithMasks(width, height, photo, globalParams, masks);
    final gpu = await renderRgbWithMasksGpu(
      width,
      height,
      photo,
      globalParams,
      masks,
    );
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
    print('[gpu_mask] $label: mean=$meanDiff max=$maxDiff');
    // Same order of tolerance as gpu_full_pipeline_test.dart (each mask
    // layer re-runs the whole ~25-pass chain), plus mask alpha's own 8-bit
    // texture quantization (mask_blend.frag's doc comment).
    expect(meanDiff, lessThan(6.0), reason: '$label: mean diff $meanDiff');
    expect(maxDiff, lessThan(32), reason: '$label: max diff $maxDiff');
  }

  group('renderRgbWithMasksGpu matches renderRgbWithMasks', () {
    testWidgets('no masks is the same as the global-only pipeline', (
      tester,
    ) async {
      await expectMatchesCpu(
        const RenderParams(exposure: 10, contrast: 15),
        const [],
        'no masks',
      );
    });

    testWidgets('linear gradient mask', (tester) async {
      await expectMatchesCpu(const RenderParams(), [
        const MaskLayer(
          id: 'm1',
          name: 'Sky',
          type: MaskType.linearGradient,
          linear: LinearGradientGeometry(
            startX: 0.5,
            startY: 0.0,
            endX: 0.5,
            endY: 0.5,
          ),
          values: {'Exposure': 40, 'Contrast': 20},
        ),
      ], 'linear gradient');
    });

    testWidgets('radial gradient mask, inverted', (tester) async {
      await expectMatchesCpu(const RenderParams(), [
        const MaskLayer(
          id: 'm1',
          name: 'Vignette area',
          type: MaskType.radialGradient,
          inverted: true,
          radial: RadialGradientGeometry(
            centerX: 0.5,
            centerY: 0.5,
            radius: 0.3,
            feather: 0.6,
          ),
          values: {'Saturation': -40, 'Highlights': -30},
        ),
      ], 'radial gradient inverted');
    });

    testWidgets('color range mask', (tester) async {
      await expectMatchesCpu(const RenderParams(), [
        const MaskLayer(
          id: 'm1',
          name: 'Blues',
          type: MaskType.colorRange,
          colorRange: ColorRangeGeometry(
            r: 60,
            g: 90,
            b: 160,
            tolerance: 35,
            feather: 30,
          ),
          values: {'Tint': 25, 'Vibrance': 30},
        ),
      ], 'color range');
    });

    testWidgets('brush mask', (tester) async {
      await expectMatchesCpu(const RenderParams(), [
        MaskLayer(
          id: 'm1',
          name: 'Dodge',
          type: MaskType.brush,
          brush: const BrushGeometry(
            strokes: [
              BrushStroke(
                points: [BrushPoint(0.3, 0.3), BrushPoint(0.6, 0.5)],
                radius: 0.15,
                hardness: 0.6,
                erase: false,
              ),
            ],
          ),
          values: const {'Exposure': 30, 'Clarity': 20},
        ),
      ], 'brush');
    });

    testWidgets('two stacked masks + opacity', (tester) async {
      await expectMatchesCpu(const RenderParams(exposure: 5), [
        const MaskLayer(
          id: 'm1',
          name: 'Top half',
          type: MaskType.linearGradient,
          opacity: 60,
          values: {'Exposure': 25, 'Contrast': 10},
        ),
        const MaskLayer(
          id: 'm2',
          name: 'Center',
          type: MaskType.radialGradient,
          radial: RadialGradientGeometry(
            centerX: 0.5,
            centerY: 0.5,
            radius: 0.25,
            feather: 0.4,
          ),
          values: {'Saturation': 30, 'SharpenAmount': 60},
        ),
      ], 'stacked masks');
    });

    testWidgets('disabled mask is skipped (matches CPU no-op)', (tester) async {
      await expectMatchesCpu(const RenderParams(exposure: 10), [
        const MaskLayer(
          id: 'm1',
          name: 'Disabled',
          type: MaskType.linearGradient,
          enabled: false,
          values: {'Exposure': 90},
        ),
      ], 'disabled mask');
    });
  });
}
