// Phase 5 of the GPU render-pipeline plan: verifies runDehazeGpu matches
// dehaze.dart's applyDehaze CPU reference, for both haze-removal (positive
// amount) and haze-addition (negative amount).
//
// Run with: flutter test integration_test/gpu_dehaze_test.dart -d windows
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/dehaze.dart';
import 'package:darkmoon/render/gpu/dehaze_gpu.dart';
import 'package:darkmoon/render/gpu/gpu_pass.dart';

/// A hazy-looking synthetic photo: a soft luminance gradient (standing in
/// for atmospheric haze washing out contrast) plus real per-channel edge
/// detail, so the dark-channel prior has genuine low-dark-channel regions
/// (the edges/shadows) and genuine near-white regions (the "sky" corner)
/// to estimate atmospheric light from.
Uint8List _syntheticHazyPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final edge = ((x ~/ 6) + (y ~/ 5)) % 2 == 0 ? 20 : 0;
      final haze = ((x + y) * 60) ~/ (width + height);
      bytes[i] = ((x * 120) ~/ width + edge + 40 + haze).clamp(0, 255);
      bytes[i + 1] = ((y * 120) ~/ height + edge + 50 + haze).clamp(0, 255);
      bytes[i + 2] = (((x + y) * 120) ~/ (width + height) + edge + 60 + haze)
          .clamp(0, 255);
    }
  }
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 96;
  const height = 72;
  final photo = _syntheticHazyPhoto(width, height);

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
    print('[gpu_dehaze] $label: mean=$meanDiff max=$maxDiff');
    // RapidRAW's apply_dehaze port: a fixed atmospheric light (no more
    // CPU<->GPU readback round trip) plus a sigma-40 Gaussian blur (3-pass
    // box-blur approximation on both sides) feeding one per-pixel apply
    // shader — tolerance kept from before this rewrite since it's still
    // comfortably wide for that approximation's own rounding.
    expect(meanDiff, lessThan(5.0), reason: '$label: mean diff $meanDiff');
    expect(maxDiff, lessThan(28), reason: '$label: max diff $maxDiff');
  }

  void runCase(String label, double amount) {
    testWidgets(label, (tester) async {
      final buffer = Float32List(photo.length);
      for (var i = 0; i < photo.length; i++) {
        buffer[i] = photo[i].toDouble();
      }
      applyDehaze(buffer, width, height, amount);
      final cpu = Uint8List(buffer.length);
      for (var i = 0; i < buffer.length; i++) {
        cpu[i] = buffer[i].clamp(0.0, 255.0).round();
      }

      final source = await decodeRgbImage(photo, width, height);
      final gpuImage = await runDehazeGpu(source, width, height, amount);
      final byteData = await gpuImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final gpu = rgbaToRgb(byteData!.buffer.asUint8List());

      expectClose(gpu, cpu, label);
    });
  }

  runCase('haze removal (positive amount)', 60);
  runCase('strong haze removal', 100);
  runCase('haze addition (negative amount)', -50);

  testWidgets('amount 0 is a no-op', (tester) async {
    final source = await decodeRgbImage(photo, width, height);
    final gpuImage = await runDehazeGpu(source, width, height, 0);
    expect(gpuImage, same(source));
  });
}
