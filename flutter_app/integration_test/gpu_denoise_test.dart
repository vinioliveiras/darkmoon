// Phase 3 of the GPU render-pipeline plan: verifies baseline chroma
// smoothing and AI denoise (classical) match their blur.dart/
// baseline_chroma.dart/ai_denoise.dart CPU counterparts.
//
// Run with: flutter test integration_test/gpu_denoise_test.dart -d windows
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/ai_denoise.dart';
import 'package:darkmoon/render/baseline_chroma.dart';
import 'package:darkmoon/render/gpu/denoise_gpu.dart';
import 'package:darkmoon/render/gpu/gpu_pass.dart';

/// Same shape as the other GPU tests' synthetic photo — real edges and
/// color variation in all 3 channels (not just luminance), so chroma
/// smoothing specifically has real chroma noise/detail to act on.
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
    print('[gpu_denoise] $label: mean=$meanDiff max=$maxDiff');
    // Wider tolerance than Phase 1/2's tests: this pipeline chains ~10
    // shader passes (blur x3 + residual + noise-var blur x2 + combine,
    // times however many baseline/AI stages run), each an 8-bit texture
    // round trip, so quantization compounds more than any single primitive
    // test saw.
    expect(meanDiff, lessThan(4.0), reason: '$label: mean diff $meanDiff');
    expect(maxDiff, lessThan(20), reason: '$label: max diff $maxDiff');
  }

  testWidgets(
    'baseline chroma smoothing matches applyBaselineChromaSmoothing',
    (tester) async {
      final buffer = Float32List(photo.length);
      for (var i = 0; i < photo.length; i++) {
        buffer[i] = photo[i].toDouble();
      }
      applyBaselineChromaSmoothing(buffer, width, height);
      final cpu = Uint8List(buffer.length);
      for (var i = 0; i < buffer.length; i++) {
        cpu[i] = buffer[i].clamp(0.0, 255.0).round();
      }

      final source = await decodeRgbImage(photo, width, height);
      final gpuImage = await runBaselineChromaSmoothingGpu(
        source,
        width,
        height,
      );
      final byteData = await gpuImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final gpu = rgbaToRgb(byteData!.buffer.asUint8List());

      expectClose(gpu, cpu, 'baseline chroma smoothing');
    },
  );

  for (final level in AiDenoiseLevel.values) {
    testWidgets('AI denoise ($level) matches applyAiDenoise', (tester) async {
      final buffer = Float32List(photo.length);
      for (var i = 0; i < photo.length; i++) {
        buffer[i] = photo[i].toDouble();
      }
      applyAiDenoise(buffer, width, height, AiDenoiseParams(level: level));
      final cpu = Uint8List(buffer.length);
      for (var i = 0; i < buffer.length; i++) {
        cpu[i] = buffer[i].clamp(0.0, 255.0).round();
      }

      final source = await decodeRgbImage(photo, width, height);
      final gpuImage = await runAiDenoiseGpu(
        source,
        width,
        height,
        AiDenoiseParams(level: level),
      );
      final byteData = await gpuImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final gpu = rgbaToRgb(byteData!.buffer.asUint8List());

      expectClose(gpu, cpu, 'AI denoise $level');
    });
  }
}
