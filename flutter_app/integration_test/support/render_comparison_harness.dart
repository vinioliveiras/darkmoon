// A shared CPU-vs-GPU comparison harness — item 7 of the Solstice-parity
// plan (translated from the original PT-BR: "Build a comparison harness.
// Generate a fixed synthetic image. Apply the same parameters in both
// projects. Export RGB buffers. Compute: mean error; max error; number of
// divergent pixels. Use a tolerance of 1 for rounding.").
//
// What this can and can't compare: renderRgb (CPU) and renderRgbGpu (GPU)
// are both this app's own implementations, so this harness verifies they
// agree with *each other* pixel-for-pixel (which is what the original
// plan's "tolerance of 1 for rounding" is really about — GPU 8-bit
// intermediate targets vs. CPU's Float32 buffer round differently). It
// can't run Solstice's own
// Rust/wgpu pipeline directly — that's a separate Tauri app, not something
// this Dart test process can invoke — so it isn't a substitute for the
// per-adjustment reference-Python-port checks already in each unit test
// file (rapid_tonal_adjustments_test.dart, color_mixer_test.dart,
// dehaze_test.dart, tone_curve_test.dart, hsl_test.dart), which were each
// cross-checked against a transcription of the relevant Solstice shader
// function. Extending this to a true three-way (CPU/GPU/Solstice)
// comparison would need a small CLI dump mode added to Solstice itself
// (decode a fixed test image, apply the same AllAdjustments, write the
// raw RGB buffer to a file) — a change to that repository, not this one.
import 'dart:typed_data';

import 'package:darkmoon/render/gpu/render_gpu.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

/// One fixed, deterministic test image (no randomness, so results are
/// reproducible run to run) built to exercise every adjustment ported from
/// Solstice in this session, not just tonal ramps:
///
/// - A per-channel gradient (rows 0..1/3 of height) for Exposure/
///   Brightness/Contrast/tone-curve/Highlights-Shadows-Whites-Blacks —
///   spans nearly the full 0-255 range including near-black and
///   near-white extremes.
/// - 8 fully saturated color patches (rows 1/3..2/3), one centered on
///   each Color Mixer/HSL band's hue (see color_mixer.dart's
///   `_hslRanges`: 358/25/60/115/180/225/280/330°) plus one skin-tone-like
///   patch (hue ~25°, lower saturation) for Vibrance's skin dampener.
/// - A checkerboard edge pattern overlaid on the bottom third for Dehaze's
///   halo-protection mask and local-contrast-style stages.
/// - A low-saturation near-gray strip along the right edge, to exercise
///   Color Mixer/Vibrance's saturation-gating (masks that fade an
///   adjustment out below ~5-20% saturation).
Uint8List buildComparisonHarnessPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);

  // Hue (degrees) + a short label for each of the 9 color patches, in
  // display order left-to-right. Saturation/value chosen so each patch
  // reads clearly as its intended hue without clipping to pure black/white.
  const patchHues = [
    358.0,
    25.0,
    25.0,
    60.0,
    115.0,
    180.0,
    225.0,
    280.0,
    330.0,
  ];
  const patchSats = [0.9, 0.9, 0.45, 0.9, 0.85, 0.85, 0.9, 0.85, 0.85];
  const patchVals = [0.75, 0.7, 0.65, 0.75, 0.6, 0.65, 0.7, 0.65, 0.7];

  List<int> hsvToRgb255(double h, double s, double v) {
    final c = v * s;
    final x = c * (1.0 - ((h / 60.0) % 2.0 - 1.0).abs());
    final m = v - c;
    List<double> rgbPrime;
    if (h < 60) {
      rgbPrime = [c, x, 0.0];
    } else if (h < 120) {
      rgbPrime = [x, c, 0.0];
    } else if (h < 180) {
      rgbPrime = [0.0, c, x];
    } else if (h < 240) {
      rgbPrime = [0.0, x, c];
    } else if (h < 300) {
      rgbPrime = [x, 0.0, c];
    } else {
      rgbPrime = [c, 0.0, x];
    }
    return [
      ((rgbPrime[0] + m) * 255).round().clamp(0, 255),
      ((rgbPrime[1] + m) * 255).round().clamp(0, 255),
      ((rgbPrime[2] + m) * 255).round().clamp(0, 255),
    ];
  }

  final gradientBand = height ~/ 3;
  final patchBand = 2 * height ~/ 3;
  final grayStripWidth = width ~/ 6;

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      int r, g, b;

      if (x >= width - grayStripWidth) {
        // Low-saturation near-gray strip, with a gentle luminance ramp so
        // it isn't a single flat value.
        final base = 60 + (y * 140) ~/ height;
        r = (base + 4).clamp(0, 255);
        g = base.clamp(0, 255);
        b = (base - 4).clamp(0, 255);
      } else if (y < gradientBand) {
        // Per-channel gradient, deliberately offset per channel so hue
        // isn't perfectly neutral gray throughout.
        r = ((x * 255) ~/ width).clamp(0, 255);
        g = (((x + width ~/ 6) * 255) ~/ width).clamp(0, 255);
        b = (((x + width ~/ 3) * 255) ~/ width).clamp(0, 255);
      } else if (y < patchBand) {
        final patchWidth = (width - grayStripWidth) ~/ patchHues.length;
        final patch = (x ~/ patchWidth).clamp(0, patchHues.length - 1);
        final rgb = hsvToRgb255(
          patchHues[patch],
          patchSats[patch],
          patchVals[patch],
        );
        r = rgb[0];
        g = rgb[1];
        b = rgb[2];
      } else {
        // Checkerboard edges over a mild haze-like gradient, for Dehaze's
        // per-pixel-vs-regional dark channel and halo protection.
        final edge = ((x ~/ 6) + (y ~/ 5)) % 2 == 0 ? 30 : 0;
        final haze = ((x + y) * 50) ~/ (width + height);
        r = (30 + edge + haze).clamp(0, 255);
        g = (45 + edge + haze).clamp(0, 255);
        b = (60 + edge + haze).clamp(0, 255);
      }

      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
    }
  }

  return bytes;
}

/// Mean/max/divergent-pixel-count comparison between [renderRgb] (CPU) and
/// [renderRgbGpu] (GPU) on the same [photo] and [params].
class RenderComparisonResult {
  const RenderComparisonResult({
    required this.meanDiff,
    required this.maxDiff,
    required this.divergentPixelBytes,
    required this.totalBytes,
    required this.tolerance,
  });

  final double meanDiff;
  final int maxDiff;

  /// Count of individual R/G/B *byte* positions (not whole pixels) whose
  /// CPU/GPU values differ by more than [tolerance].
  final int divergentPixelBytes;
  final int totalBytes;
  final int tolerance;

  double get divergentFraction => divergentPixelBytes / totalBytes;

  @override
  String toString() =>
      'mean=${meanDiff.toStringAsFixed(3)} max=$maxDiff '
      'divergent=$divergentPixelBytes/$totalBytes '
      '(${(divergentFraction * 100).toStringAsFixed(2)}%, tolerance=$tolerance)';
}

/// Runs [params] through both renderers on [photo] and compares the
/// results — the "tolerance of 1 for rounding" from the plan this
/// harness implements: a byte-level diff of 1 is expected GPU/CPU rounding
/// noise (different intermediate precision), not a bug, so
/// [divergentPixelBytes] counts only diffs strictly greater than
/// [tolerance].
Future<RenderComparisonResult> compareRenderers(
  int width,
  int height,
  Uint8List photo,
  RenderParams params, {
  int tolerance = 1,
}) async {
  final cpu = renderRgb(width, height, photo, params);
  final gpu = await renderRgbGpu(width, height, photo, params);
  assert(cpu.length == gpu.length, 'byte length mismatch');

  var sumDiff = 0.0;
  var maxDiff = 0;
  var divergent = 0;
  for (var i = 0; i < cpu.length; i++) {
    final d = (cpu[i] - gpu[i]).abs();
    sumDiff += d;
    if (d > maxDiff) maxDiff = d;
    if (d > tolerance) divergent++;
  }

  return RenderComparisonResult(
    meanDiff: sumDiff / cpu.length,
    maxDiff: maxDiff,
    divergentPixelBytes: divergent,
    totalBytes: cpu.length,
    tolerance: tolerance,
  );
}
