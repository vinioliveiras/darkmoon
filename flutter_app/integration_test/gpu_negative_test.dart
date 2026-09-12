// GPU/CPU parity for the negative conversion (negative.frag vs
// negative.dart's applyNegative): the same synthetic negative, the same
// measured bounds, the same sliders, on both paths — as the first stage
// of a render with Exposure and White Balance moved too, which is where
// it sits.
//
// Run with: bash tool/gpu_test.sh integration_test/gpu_negative_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/gpu/render_gpu.dart';
import 'package:darkmoon/render/negative.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

/// A colour negative: a scene gradient under an orange mask, with a
/// checker so the density range has texture in it.
Uint8List _negativePhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final scene = ((x / (width - 1)) * 0.7 + (y / (height - 1)) * 0.3);
      final edge = ((x ~/ 11) + (y ~/ 7)) % 2 == 0 ? 0.06 : 0.0;
      final neg = (1 - scene + edge).clamp(0.0, 1.0);
      bytes[i] = (40 + neg * 200).round().clamp(0, 255);
      bytes[i + 1] = (25 + neg * 170).round().clamp(0, 255);
      bytes[i + 2] = (15 + neg * 120).round().clamp(0, 255);
    }
  }
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 96;
  const height = 64;
  final photo = _negativePhoto(width, height);
  final bounds = analyzeNegativeBounds(photo, width, height);

  Future<void> expectMatchesCpu(RenderParams params, String label) async {
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
    final mean = sumDiff / cpu.length;
    // ignore: avoid_print
    print('$label: mean $mean, max $maxDiff');
    expect(mean, lessThan(1.5), reason: '$label: mean diff $mean');
    expect(maxDiff, lessThan(8), reason: '$label: max diff $maxDiff');
  }

  testWidgets('default conversion matches the CPU', (tester) async {
    await expectMatchesCpu(
      RenderParams(
        negative: const NegativeParams(enabled: true),
        negativeBounds: bounds,
      ),
      'negative default',
    );
  });

  testWidgets('weights, exposure and contrast match the CPU', (tester) async {
    await expectMatchesCpu(
      RenderParams(
        negative: const NegativeParams(
          enabled: true,
          redWeight: 1.15,
          greenWeight: 0.95,
          blueWeight: 1.05,
          exposure: 0.4,
          contrast: 1.5,
        ),
        negativeBounds: bounds,
      ),
      'negative tuned',
    );
  });

  testWidgets('conversion followed by exposure and white balance matches', (
    tester,
  ) async {
    await expectMatchesCpu(
      RenderParams(
        negative: const NegativeParams(enabled: true),
        negativeBounds: bounds,
        exposure: 0.5,
        temperature: 6200,
        tint: 6,
        contrast: 15,
      ),
      'negative + wb',
    );
  });

  testWidgets('the conversion actually inverts the image', (tester) async {
    final plain = renderRgb(width, height, photo, const RenderParams());
    final positive = renderRgb(
      width,
      height,
      photo,
      RenderParams(
        negative: const NegativeParams(enabled: true),
        negativeBounds: bounds,
      ),
    );
    // Left edge (bright scene, dark on the negative) is now brighter
    // than the right edge, the opposite of the input.
    double luma(Uint8List px, int x) {
      final i = (height ~/ 2 * width + x) * 3;
      return 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
    }

    expect(luma(plain, 0), greaterThan(luma(plain, width - 1)));
    expect(luma(positive, 0), lessThan(luma(positive, width - 1)));
  });
}
