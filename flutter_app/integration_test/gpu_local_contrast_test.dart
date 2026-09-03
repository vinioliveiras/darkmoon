// Phase 4 of the GPU render-pipeline plan: verifies runLocalContrastGpu
// matches local_contrast.dart's applyLocalContrast CPU reference, for both
// its Texture (small sigma, noiseAware) and Clarity (large sigma,
// protectMidtones) call shapes.
//
// Run with: flutter test integration_test/gpu_local_contrast_test.dart -d windows
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/gpu/gpu_pass.dart';
import 'package:darkmoon/render/gpu/local_contrast_gpu.dart';
import 'package:darkmoon/render/local_contrast.dart';

Uint8List _syntheticPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final edge = ((x ~/ 6) + (y ~/ 5)) % 2 == 0 ? 25 : 0;
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

  const width = 96;
  const height = 72;
  final photo = _syntheticPhoto(width, height);

  void expectClose(Uint8List gpu, Uint8List cpu, String label) {
    var sumDiff = 0.0;
    var maxDiff = 0;
    for (var i = 0; i < cpu.length; i++) {
      final d = (cpu[i] - gpu[i]).abs();
      sumDiff += d;
      if (d > maxDiff) maxDiff = d;
    }
    final meanDiff = sumDiff / cpu.length;
    // ignore: avoid_print
    print('[gpu_local_contrast] $label: mean=$meanDiff max=$maxDiff');
    // Tightened from 4.0/24 once residual_sq.frag stopped quantizing the
    // local noise variance to zero (2026-09-03) — that bug alone was worth
    // ~1.4 mean / 5 max on the noiseAware (Texture) cases, and the old
    // headroom was wide enough to hide it completely. Measured worst case
    // across these four cases is now 0.50 mean / 3 max; this keeps roughly
    // 2x of that, enough for driver-to-driver rounding without leaving
    // room for a regression of the same class to slip through again.
    expect(meanDiff, lessThan(1.2), reason: '$label: mean diff $meanDiff');
    expect(maxDiff, lessThan(8), reason: '$label: max diff $maxDiff');
  }

  void runCase(
    String label,
    double amount,
    double sigma, {
    bool protectMidtones = false,
    bool noiseAware = false,
  }) {
    testWidgets(label, (tester) async {
      final buffer = Float32List(photo.length);
      for (var i = 0; i < photo.length; i++) {
        buffer[i] = photo[i].toDouble();
      }
      applyLocalContrast(
        buffer,
        width,
        height,
        amount,
        sigma,
        protectMidtones: protectMidtones,
        noiseAware: noiseAware,
      );
      final cpu = Uint8List(buffer.length);
      for (var i = 0; i < buffer.length; i++) {
        cpu[i] = buffer[i].clamp(0.0, 255.0).round();
      }

      final source = await decodeRgbImage(photo, width, height);
      final gpuImage = await runLocalContrastGpu(
        source,
        width,
        height,
        amount,
        sigma,
        protectMidtones: protectMidtones,
        noiseAware: noiseAware,
      );
      final byteData = await gpuImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final gpu = rgbaToRgb(byteData!.buffer.asUint8List());

      expectClose(gpu, cpu, label);
    });
  }

  // Texture's real call shape: small sigma, noise-aware.
  runCase('Texture (sigma=3, noiseAware)', 60, 3.0, noiseAware: true);
  // Clarity's real call shape: large sigma, midtone-protected.
  runCase(
    'Clarity (sigma=25, protectMidtones)',
    60,
    25.0,
    protectMidtones: true,
  );
  // Both flags together, to exercise the combine shader's full branch set.
  runCase(
    'both flags active',
    80,
    10.0,
    protectMidtones: true,
    noiseAware: true,
  );
  // Negative amount (reduce local contrast) — legal per Clarity/Texture's
  // slider range, exercises the sign of highFreq*gain.
  runCase('negative amount', -50, 25.0, protectMidtones: true);

  testWidgets('amount 0 is a no-op', (tester) async {
    final source = await decodeRgbImage(photo, width, height);
    final gpuImage = await runLocalContrastGpu(
      source,
      width,
      height,
      0,
      25.0,
      protectMidtones: true,
    );
    expect(gpuImage, same(source));
  });
}
