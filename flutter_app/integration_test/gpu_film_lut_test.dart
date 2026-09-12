// GPU/CPU parity for the Film stage (film_lut.frag vs film_lut.dart's
// applyFilmLut): the same table, the same photo, the same amount, on both
// paths. The table is a real non-identity one (a swap plus a lift), and
// the pass runs with Grain and Vignette on too so it is measured where it
// actually sits — last, after post_dehaze.frag.
//
// Run with: bash tool/gpu_test.sh integration_test/gpu_film_lut_test.dart

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/film_lut.dart';
import 'package:darkmoon/render/gpu/render_gpu.dart';
import 'package:darkmoon/render/grain.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
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

/// A table that is nothing like the identity: channels rotated, green
/// lifted, blue crushed — so a missing or misaligned pass cannot pass.
FilmLut _lookLut() {
  const size = filmLutSize;
  final data = Uint8List(size * size * size * 3);
  var k = 0;
  for (var b = 0; b < size; b++) {
    for (var g = 0; g < size; g++) {
      for (var r = 0; r < size; r++) {
        final rn = r / (size - 1), gn = g / (size - 1), bn = b / (size - 1);
        data[k++] = ((0.7 * gn + 0.3 * rn) * 255).round();
        data[k++] = ((0.25 + 0.75 * bn) * 255).round();
        data[k++] = ((rn * rn) * 255).round();
      }
    }
  }
  return FilmLut(size: size, data: data);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 96;
  const height = 64;
  final photo = _syntheticPhoto(width, height);
  final lut = _lookLut();

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

  testWidgets('film at full amount matches the CPU', (tester) async {
    await expectMatchesCpu(
      RenderParams(filmLut: lut, filmAmount: 1.0),
      'film 100%',
    );
  });

  testWidgets('film at half amount matches the CPU', (tester) async {
    await expectMatchesCpu(
      RenderParams(filmLut: lut, filmAmount: 0.5),
      'film 50%',
    );
  });

  testWidgets('film after contrast, saturation and vignette matches the '
      'CPU', (tester) async {
    await expectMatchesCpu(
      RenderParams(
        filmLut: lut,
        filmAmount: 0.8,
        contrast: 20,
        saturation: 15,
        vignette: const VignetteParams(amount: -40),
      ),
      'film + vignette',
    );
  });

  testWidgets('film after grain matches the CPU', (tester) async {
    // Grain's per-pixel hash noise is where the two paths already differ
    // by up to ~24 levels on single pixels (gpu_point_ops_test's own
    // tolerance); the table only has to not widen that.
    await expectMatchesCpu(
      RenderParams(
        filmLut: lut,
        filmAmount: 0.8,
        grain: const GrainParams(amount: 30),
      ),
      'film + grain',
      maxTolerance: 25,
    );
  });

  testWidgets('film actually changes the image', (tester) async {
    final plain = renderRgb(width, height, photo, const RenderParams());
    final filmed = renderRgb(
      width,
      height,
      photo,
      RenderParams(filmLut: lut, filmAmount: 1.0),
    );
    var changed = 0;
    for (var i = 0; i < plain.length; i++) {
      if ((plain[i] - filmed[i]).abs() > 8) changed++;
    }
    expect(changed, greaterThan(plain.length ~/ 2));
  });
}
