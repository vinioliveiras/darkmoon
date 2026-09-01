// Phase 4 of the GPU render-pipeline plan: verifies runSharpenGpu matches
// sharpen.dart's applySharpen CPU reference.
//
// Run with: flutter test integration_test/gpu_sharpen_test.dart -d windows
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/gpu/gpu_pass.dart';
import 'package:darkmoon/render/gpu/sharpen_gpu.dart';
import 'package:darkmoon/render/sharpen.dart';

/// Same shape as the other GPU tests' synthetic photo — real edges and
/// per-channel variation so both the unsharp-mask residual and the
/// edge-aware masking term have real signal to act on.
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
    print('[gpu_sharpen] $label: mean=$meanDiff max=$maxDiff');
    // Same wider tolerance as gpu_denoise_test.dart's — this chains
    // several blur passes (main + fine + edge-strength) plus a
    // residual/noise-var pass, each an 8-bit texture round trip.
    expect(meanDiff, lessThan(4.0), reason: '$label: mean diff $meanDiff');
    expect(maxDiff, lessThan(24), reason: '$label: max diff $maxDiff');
  }

  Future<void> runCase(String label, SharpenParams params) async {
    testWidgets(label, (tester) async {
      final buffer = Float32List(photo.length);
      for (var i = 0; i < photo.length; i++) {
        buffer[i] = photo[i].toDouble();
      }
      applySharpen(buffer, width, height, params);
      final cpu = Uint8List(buffer.length);
      for (var i = 0; i < buffer.length; i++) {
        cpu[i] = buffer[i].clamp(0.0, 255.0).round();
      }

      final source = await decodeRgbImage(photo, width, height);
      final gpuImage = await runSharpenGpu(source, width, height, params);
      final byteData = await gpuImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final gpu = rgbaToRgb(byteData!.buffer.asUint8List());

      expectClose(gpu, cpu, label);
    });
  }

  runCase('default (Meridian-style RAW-import) params', const SharpenParams());
  runCase(
    'amount only, no detail/masking',
    const SharpenParams(amount: 80, detail: 0, masking: 0),
  );
  runCase(
    'detail blend active',
    const SharpenParams(amount: 60, radius: 1.5, detail: 70, masking: 0),
  );
  runCase(
    'edge masking active',
    const SharpenParams(amount: 60, radius: 1.0, detail: 0, masking: 80),
  );
  runCase(
    'detail + masking both active',
    const SharpenParams(amount: 100, radius: 2.0, detail: 50, masking: 50),
  );
  runCase('identity (amount 0) is a no-op', const SharpenParams(amount: 0));
}
