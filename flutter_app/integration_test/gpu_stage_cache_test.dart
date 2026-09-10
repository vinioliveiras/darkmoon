// GpuStageCache correctness: a render that resumes from a cached stage
// must produce exactly what a cold render of the same parameters does. Run
// on a real device (see gpu_timing_probe_test.dart's header for how, on a
// machine where `flutter test integration_test` itself is unreliable).
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

  const width = 320, height = 200;
  Uint8List makePhoto(int seed) {
    final photo = Uint8List(width * height * 3);
    final rng = math.Random(seed);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 3;
        // A gradient with noise, so blurs and denoise have real work.
        photo[i] = ((x * 255 / width) + rng.nextInt(24) - 12)
            .clamp(0, 255)
            .toInt();
        photo[i + 1] = ((y * 255 / height) + rng.nextInt(24) - 12)
            .clamp(0, 255)
            .toInt();
        photo[i + 2] = (128 + rng.nextInt(24) - 12).clamp(0, 255);
      }
    }
    return photo;
  }

  final photo = makePhoto(1);

  Future<Uint8List> cold(RenderParams params, [Uint8List? source]) async {
    GpuStageCache.enabled = false;
    try {
      return await renderRgbGpu(width, height, source ?? photo, params);
    } finally {
      GpuStageCache.enabled = true;
    }
  }

  Future<(Uint8List, int)> warmThen(
    RenderParams warm,
    RenderParams then, [
    Uint8List? source,
  ]) async {
    GpuStageCache.enabled = true;
    GpuStageCache.instance.clear();
    await renderRgbGpu(width, height, source ?? photo, warm);
    GpuPass.resetPassCount();
    final out = await renderRgbGpu(width, height, source ?? photo, then);
    final passes = GpuPass.passCount;
    GpuStageCache.instance.clear();
    return (out, passes);
  }

  const base = RenderParams(
    exposure: 0.5,
    sharpen: SharpenParams(amount: 40),
    texture: 20,
    clarity: 15,
    dehaze: 10,
    shadows: 20,
  );

  testWidgets('a point-op change resumes from afterDehaze and matches a '
      'cold render byte for byte', (tester) async {
    const changed = RenderParams(
      exposure: 0.5,
      sharpen: SharpenParams(amount: 40),
      texture: 20,
      clarity: 15,
      dehaze: 10,
      shadows: 20,
      contrast: 25,
      vibrance: 15,
    );
    final (cached, passes) = await warmThen(base, changed);
    GpuPass.resetPassCount();
    final reference = await cold(changed);
    final coldCount = GpuPass.passCount;
    expect(cached, reference);
    expect(passes, lessThan(coldCount));
    // Tonal blur (srgb_to_linear + 3 box passes) + two point-op passes.
    expect(passes, lessThanOrEqualTo(6));
  });

  testWidgets('a Detail-panel change resumes from afterAiDenoise and '
      'matches a cold render', (tester) async {
    const changed = RenderParams(
      exposure: 0.5,
      sharpen: SharpenParams(amount: 80, radius: 1.8),
      texture: 20,
      clarity: 15,
      dehaze: 10,
      shadows: 20,
    );
    final (cached, passes) = await warmThen(base, changed);
    GpuPass.resetPassCount();
    final reference = await cold(changed);
    final coldCount = GpuPass.passCount;
    expect(cached, reference);
    expect(passes, lessThan(coldCount));
  });

  testWidgets('an Exposure change misses both boundaries and still matches', (
    tester,
  ) async {
    const changed = RenderParams(
      exposure: 1.5,
      sharpen: SharpenParams(amount: 40),
      texture: 20,
      clarity: 15,
      dehaze: 10,
      shadows: 20,
    );
    final (cached, passes) = await warmThen(base, changed);
    GpuPass.resetPassCount();
    final reference = await cold(changed);
    final coldCount = GpuPass.passCount;
    expect(cached, reference);
    expect(passes, coldCount);
  });

  testWidgets('a different photo never resumes from the previous one', (
    tester,
  ) async {
    final other = makePhoto(2);
    GpuStageCache.enabled = true;
    GpuStageCache.instance.clear();
    await renderRgbGpu(width, height, photo, base);
    final cached = await renderRgbGpu(width, height, other, base);
    GpuStageCache.instance.clear();
    final reference = await cold(base, other);
    expect(cached, reference);
  });

  testWidgets('the same parameters twice hit the deepest boundary and '
      'render the same bytes', (tester) async {
    final (cached, passes) = await warmThen(base, base);
    final reference = await cold(base);
    expect(cached, reference);
    expect(passes, lessThanOrEqualTo(6));
  });

  testWidgets('a no-op stage right after a cached boundary hands the '
      'cached image through without the chain reclaiming it', (tester) async {
    // Sharpen at 0 returns afterAiDenoise itself as afterSharpen; the
    // chain must not re-register (and then dispose) the image the cache
    // now owns. The next render replaces both entries, which disposes the
    // old ones — a second dispose of a reclaimed image is a dart:ui
    // assertion. Found by gpu_point_ops_test on 2026-09-09.
    const noSharpen = RenderParams(
      exposure: 0.5,
      sharpen: SharpenParams(amount: 0),
      dehaze: 20,
    );
    const otherExposure = RenderParams(
      exposure: 0.9,
      sharpen: SharpenParams(amount: 0),
      dehaze: 20,
    );
    GpuStageCache.enabled = true;
    GpuStageCache.instance.clear();
    await renderRgbGpu(width, height, photo, noSharpen);
    final a = await renderRgbGpu(width, height, photo, otherExposure);
    final b = await renderRgbGpu(width, height, photo, noSharpen);
    GpuStageCache.instance.clear();
    expect(a, await cold(otherExposure));
    expect(b, await cold(noSharpen));
  });

  testWidgets('an all-identity middle section (one image at both '
      'boundaries) survives replacement without a double dispose', (
    tester,
  ) async {
    // sharpen 0, texture/clarity/dehaze 0, baseContrast 0, no profile:
    // every stage between the boundaries hands its input through, so the
    // cache holds one ui.Image under both keys. Replacing one boundary
    // must not dispose the other's image.
    const identityMiddle = RenderParams(
      exposure: 0.5,
      sharpen: SharpenParams(amount: 0),
      baseContrast: 0,
    );
    const thenSharpen = RenderParams(
      exposure: 0.5,
      sharpen: SharpenParams(amount: 50),
      baseContrast: 0,
    );
    GpuStageCache.enabled = true;
    GpuStageCache.instance.clear();
    await renderRgbGpu(width, height, photo, identityMiddle);
    // Resumes from afterAiDenoise (shared image), stores a new afterDehaze
    // — the old afterDehaze entry is that same shared image and must stay.
    final a = await renderRgbGpu(width, height, photo, thenSharpen);
    // Now resume from afterAiDenoise again: the shared image must still be
    // alive.
    final b = await renderRgbGpu(width, height, photo, identityMiddle);
    GpuStageCache.instance.clear();
    expect(a, await cold(thenSharpen));
    expect(b, await cold(identityMiddle));
  });
}
