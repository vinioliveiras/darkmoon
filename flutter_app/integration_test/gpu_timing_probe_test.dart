// Temporary measurement harness (not a regression test): times the GPU
// pipeline stage-group by stage-group at a realistic editing resolution,
// so a decision about fusing passes or downsampling the wide blurs is
// made on numbers rather than on the pass count.
//
// How to run on a machine where `flutter test integration_test/...` loses
// the VM service (Flutter 3.47.2 on Windows, 2026-09-09):
//
//   bash tool/gpu_test.sh integration_test/gpu_timing_probe_test.dart
//
// which drives the file through `flutter run`, prints the measurement
// lines, and closes the app the moment the summary appears.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:darkmoon/render/gpu/gpu_pass.dart';
import 'package:darkmoon/render/gpu/gpu_stage_cache.dart';
import 'package:darkmoon/render/gpu/render_gpu.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/sharpen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // 6 MP — roughly what a 40% full-quality preview of a 40 MP sensor is.
  const width = 3000, height = 2000;
  final photo = Uint8List(width * height * 3);
  final rng = math.Random(7);
  for (var i = 0; i < photo.length; i++) {
    photo[i] = rng.nextInt(256);
  }

  Future<int> timeRender(String label, RenderParams params) async {
    // The stage cost of the *cold* chain — the cache would turn the
    // repeated runs below into two-pass renders.
    GpuStageCache.enabled = false;
    GpuStageCache.instance.clear();
    // One warm-up so shader compilation isn't charged to the measurement.
    await renderRgbaGpu(width, height, photo, params);
    GpuPass.resetPassCount();
    final sw = Stopwatch()..start();
    const runs = 3;
    for (var i = 0; i < runs; i++) {
      await renderRgbaGpu(width, height, photo, params);
    }
    final ms = sw.elapsedMilliseconds ~/ runs;
    final passes = GpuPass.passCount ~/ runs;
    final perPass = passes == 0 ? 0 : ms / passes;
    // ignore: avoid_print
    print(
      '[gpu_timing] ${label.padRight(34)} ${ms}ms  '
      '$passes passes  ${perPass.toStringAsFixed(1)}ms/pass',
    );
    final breakdown = GpuPass.passCountByShader.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // ignore: avoid_print
    print(
      '[gpu_timing]   ${breakdown.map((e) => '${e.key.split('/').last.replaceAll('.frag', '')}x${e.value ~/ runs}').join(' ')}',
    );
    return ms;
  }

  testWidgets('stage cost breakdown at ${width}x$height', (tester) async {
    final baseline = await timeRender(
      'baseline (chroma smoothing only)',
      const RenderParams(baseContrast: 0),
    );
    await timeRender(
      '+ tone (no extra passes)',
      const RenderParams(baseContrast: 0, exposure: 6, contrast: 20),
    );
    await timeRender(
      '+ shadows (adds tonal blur)',
      const RenderParams(baseContrast: 0, shadows: 40),
    );
    await timeRender(
      '+ texture (sigma 3.5)',
      const RenderParams(baseContrast: 0, texture: 40),
    );
    await timeRender(
      '+ clarity (sigma 35)',
      const RenderParams(baseContrast: 0, clarity: 40),
    );
    await timeRender(
      '+ dehaze (sigma 40)',
      const RenderParams(baseContrast: 0, dehaze: 40),
    );
    await timeRender(
      '+ sharpen',
      const RenderParams(baseContrast: 0, sharpen: SharpenParams(amount: 50)),
    );
    await timeRender(
      'everything',
      const RenderParams(
        baseContrast: 80,
        exposure: 6,
        shadows: 40,
        texture: 40,
        clarity: 40,
        dehaze: 40,
        sharpen: SharpenParams(amount: 50),
      ),
    );
    expect(baseline, greaterThan(0));

    // The stage cache's case: the same photo, one slider moving. Each timed
    // render changes Contrast so nothing is a pure repeat, and every one
    // resumes from afterDehaze.
    Future<void> timeCachedDrag(
      String label,
      RenderParams Function(double contrast) build,
    ) async {
      GpuStageCache.enabled = true;
      GpuStageCache.instance.clear();
      await renderRgbaGpu(width, height, photo, build(0));
      GpuPass.resetPassCount();
      final sw = Stopwatch()..start();
      const runs = 3;
      for (var i = 1; i <= runs; i++) {
        await renderRgbaGpu(width, height, photo, build(i * 10.0));
      }
      final ms = sw.elapsedMilliseconds ~/ runs;
      final passes = GpuPass.passCount ~/ runs;
      // ignore: avoid_print
      print(
        '[gpu_timing] ${label.padRight(34)} ${ms}ms  '
        '$passes passes  (stage cache, Contrast drag)',
      );
      GpuStageCache.instance.clear();
    }

    await timeCachedDrag(
      'cached: default + contrast',
      (c) => RenderParams(baseContrast: 0, contrast: c),
    );
    await timeCachedDrag(
      'cached: everything + contrast',
      (c) => RenderParams(
        baseContrast: 80,
        exposure: 6,
        shadows: 40,
        texture: 40,
        clarity: 40,
        dehaze: 40,
        sharpen: const SharpenParams(amount: 50),
        contrast: c,
      ),
    );
  });
}
