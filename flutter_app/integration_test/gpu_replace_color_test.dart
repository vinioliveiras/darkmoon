// GPU/CPU parity for Replace color (replace_color.frag vs
// replace_color.dart's applyReplaceColor): the same picked colour, range,
// softness and moves on both paths, measured where the stage sits — last,
// after Film, Grain and Vignette.
//
// Run with: bash tool/gpu_test.sh integration_test/gpu_replace_color_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/film_lut.dart';
import 'package:darkmoon/render/gpu/render_gpu.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/replace_color.dart';
import 'package:darkmoon/render/vignette.dart';

Uint8List _syntheticPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final edge = ((x ~/ 17) + (y ~/ 13)) % 2 == 0 ? 20 : 0;
      bytes[i] = ((x * 230) ~/ width + edge).clamp(0, 255);
      bytes[i + 1] = ((y * 230) ~/ height + edge).clamp(0, 255);
      bytes[i + 2] = (((x + y) * 230) ~/ (width + height) + edge).clamp(0, 255);
    }
  }
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 96;
  const height = 64;
  final photo = _syntheticPhoto(width, height);

  Future<void> expectMatchesCpu(
    RenderParams params,
    String label, {
    int maxTolerance = 8,
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
    final mean = sumDiff / cpu.length;
    // ignore: avoid_print
    print('$label: mean $mean, max $maxDiff');
    expect(mean, lessThan(1.5), reason: '$label: mean diff $mean');
    expect(
      maxDiff,
      lessThan(maxTolerance),
      reason: '$label: max diff $maxDiff',
    );
  }

  const pick = ReplaceColorParams(
    picked: true,
    r: 180,
    g: 120,
    b: 140,
    tolerance: 25,
    feather: 40,
    hue: 75,
    saturation: 30,
    luminance: -20,
    amount: 100,
  );

  testWidgets('replace colour at full amount matches the CPU', (tester) async {
    // The GPU reads an 8-bit texture, so a pixel that sits right at the
    // range's edge can fall on the other side of the hard threshold —
    // measured mean 0.95, max 9 (2026-09-13).
    await expectMatchesCpu(
      const RenderParams(replaceColor: pick),
      'replace 100%',
      maxTolerance: 12,
    );
  });

  testWidgets('replace colour at half amount, after vignette and film, '
      'matches the CPU', (tester) async {
    await expectMatchesCpu(
      RenderParams(
        replaceColor: const ReplaceColorParams(
          picked: true,
          r: 180,
          g: 120,
          b: 140,
          tolerance: 25,
          feather: 40,
          hue: -60,
          saturation: -40,
          luminance: 25,
          amount: 50,
        ),
        vignette: const VignetteParams(amount: -40),
        filmLut: FilmLut.identity(filmLutSize),
        filmAmount: 1.0,
      ),
      'replace 50% + vignette + film',
      // Measured mean 0.98, max 8.
      maxTolerance: 12,
    );
  });
}
