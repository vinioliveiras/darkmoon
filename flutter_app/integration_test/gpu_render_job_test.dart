// The GPU render job as the editor consumes it (2026-09-11): the canvas
// paints the GPU's own image, and only a reduced readback comes back for
// the histogram and the filmstrip thumbnail. Checks that histogram
// against the full frame's, and times the old full-readback shape
// against the new one on a default-size preview.
//
// Run with: bash tool/gpu_test.sh integration_test/gpu_render_job_test.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/native/edit_source.dart';
import 'package:darkmoon/render/gpu/render_job_gpu.dart';
import 'package:darkmoon/render/histogram.dart';
import 'package:darkmoon/render/render_job.dart';
import 'package:darkmoon/render/render_params.dart';

Uint8List _syntheticPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final edge = ((x ~/ 23) + (y ~/ 17)) % 2 == 0 ? 30 : 0;
      final noise = (x * 7 + y * 13) % 11;
      bytes[i] = ((x * 200) ~/ width + edge + noise).clamp(0, 255);
      bytes[i + 1] = ((y * 200) ~/ height + edge + 30).clamp(0, 255);
      bytes[i + 2] = (((x + y) * 200) ~/ (width + height) + edge + 50).clamp(
        0,
        255,
      );
    }
  }
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 3072;
  const height = 2048;
  final photo = _syntheticPhoto(width, height);
  final source = EditSource(width: width, height: height, rgbBytes: photo);
  const params = RenderParams(
    exposure: 0.3,
    contrast: 15,
    clarity: 20,
    dehaze: 20,
    vibrance: 10,
  );
  final job = RenderJob(source: source, params: params);

  testWidgets('the reduced readback\'s histogram matches the full frame\'s', (
    tester,
  ) async {
    final result = await renderJobToImageGpu(job);
    final full = await result.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    result.image.dispose();
    final reference = computeHistogram(full!.buffer.asUint8List(), channels: 4);

    double maxBinDiff(List<int> a, List<int> b) {
      final totalA = a.fold<int>(0, (s, v) => s + v);
      final totalB = b.fold<int>(0, (s, v) => s + v);
      var worst = 0.0;
      for (var i = 0; i < a.length; i++) {
        final d = (a[i] / totalA - b[i] / totalB).abs();
        if (d > worst) worst = d;
      }
      return worst;
    }

    final worst = [
      maxBinDiff(reference.red, result.histogram.red),
      maxBinDiff(reference.green, result.histogram.green),
      maxBinDiff(reference.blue, result.histogram.blue),
    ].reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print(
      '[gpu_render_job] histogram worst bin difference (fraction of pixels): '
      '${worst.toStringAsFixed(5)}',
    );
    expect(worst, lessThan(0.005));
    expect(result.thumbnailBytes, isNotEmpty);
  });

  testWidgets('timing: full readback + upload against image hand-off', (
    tester,
  ) async {
    Future<ui.Image> upload(RenderResult r) {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        r.previewRgba,
        r.previewWidth,
        r.previewHeight,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      return completer.future;
    }

    // Warm both (shader compile, stage cache).
    (await upload(await renderJobToJpegGpu(job))).dispose();
    (await renderJobToImageGpu(job)).image.dispose();

    const rounds = 4;
    final sw = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      (await upload(await renderJobToJpegGpu(job))).dispose();
    }
    final oldMs = sw.elapsedMilliseconds / rounds;
    sw.reset();
    for (var i = 0; i < rounds; i++) {
      (await renderJobToImageGpu(job)).image.dispose();
    }
    final newMs = sw.elapsedMilliseconds / rounds;
    // ignore: avoid_print
    print(
      '[gpu_render_job] ${width}x$height settled render: full readback + '
      'upload ${oldMs.toStringAsFixed(0)} ms, image hand-off '
      '${newMs.toStringAsFixed(0)} ms',
    );
    expect(newMs, lessThan(oldMs));
  });
}
