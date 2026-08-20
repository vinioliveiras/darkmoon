import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/ai_denoise.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/render_parallel.dart';
import 'package:darkmoon/render/sharpen.dart';

/// A deterministic, non-trivial (not flat, not simply periodic in a way
/// that could hide a misaligned seam) RGB pattern — real edges and
/// gradients in both directions, so a wrong halo would show up as an
/// actual pixel difference at a band boundary, not just get lost in flat
/// color. Tall enough that even Clarity's much bigger halo still leaves
/// room for several real bands (`renderAdjustmentsParallel`'s own
/// minimum-content-per-band guard would otherwise silently fall back to a
/// single band for the Clarity-active cases below, on a shorter image —
/// which would make those tests pass without ever actually exercising
/// the multi-band path they're named for).
Uint8List _syntheticPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final edge = ((x ~/ 37) + (y ~/ 29)) % 2 == 0 ? 40 : 0;
      bytes[i] = ((x * 255) ~/ width + edge).clamp(0, 255);
      bytes[i + 1] = ((y * 255) ~/ height + edge).clamp(0, 255);
      bytes[i + 2] = (((x + y) * 255) ~/ (width + height) + edge).clamp(0, 255);
    }
  }
  return bytes;
}

void main() {
  const width = 1200;
  const height = 3600;
  final photo = _syntheticPhoto(width, height);

  Future<void> expectMatchesSerial(RenderParams params, String label) async {
    final serial = renderRgb(width, height, photo, params);
    final parallel = await renderAdjustmentsParallel(
      width,
      height,
      photo,
      params,
    );
    expect(
      parallel.length,
      serial.length,
      reason: '$label: byte length mismatch',
    );
    var maxDiff = 0;
    var diffCount = 0;
    for (var i = 0; i < serial.length; i++) {
      final d = (serial[i] - parallel[i]).abs();
      if (d > 0) {
        diffCount++;
        if (d > maxDiff) {
          maxDiff = d;
        }
      }
    }
    // Not a strict ==0 check: `Isolate.run` computes in a different
    // isolate, and floating-point ops can differ in their very last bit
    // depending on how the compiler/runtime schedules them — a 1-value
    // rounding wobble here and there is expected noise, not a seam bug. A
    // *systematic* seam (wrong halo) shows up as either many more diffs
    // than a few stray rounding pixels, or a diff bigger than rounding
    // noise could ever produce.
    expect(
      maxDiff,
      lessThanOrEqualTo(1),
      reason:
          '$label: found a difference of $maxDiff — bigger than '
          'floating-point rounding noise, likely a band-seam bug',
    );
    expect(
      diffCount,
      lessThan(serial.length ~/ 1000),
      reason:
          '$label: $diffCount pixel bytes differ from the serial '
          'render — too many to be stray rounding, likely a wrong halo',
    );
  }

  group('renderAdjustmentsParallel matches renderRgb (the serial path)', () {
    test('neutral params (still exercises baseline chroma smoothing, '
        'which is always on)', () async {
      await expectMatchesSerial(const RenderParams(), 'neutral');
    });

    test('sharpen active (exercises the sharpen halo)', () async {
      await expectMatchesSerial(
        const RenderParams(sharpen: SharpenParams(amount: 80, radius: 3.0)),
        'sharpen',
      );
    });

    test('texture and clarity active (exercises the largest halo, '
        "clarity's sigma=25 blur)", () async {
      await expectMatchesSerial(
        const RenderParams(texture: 90, clarity: -70),
        'texture+clarity',
      );
    });

    test('ai denoise active (exercises the ai-denoise halo)', () async {
      await expectMatchesSerial(
        const RenderParams(
          aiDenoise: AiDenoiseParams(level: AiDenoiseLevel.strong),
        ),
        'aiDenoise',
      );
    });

    test('dehaze active (a global-statistic step — must run once on the '
        'stitched-back-together buffer, not per-band)', () async {
      await expectMatchesSerial(const RenderParams(dehaze: 70), 'dehaze');
    });

    test('everything active at once (worst-case combined halo)', () async {
      await expectMatchesSerial(
        const RenderParams(
          temperature: 7000,
          tint: 30,
          exposure: 20,
          contrast: 15,
          highlights: -20,
          shadows: 30,
          sharpen: SharpenParams(amount: 100, radius: 2.5, masking: 40),
          texture: 60,
          clarity: 60,
          dehaze: 40,
          vibrance: 30,
          saturation: 20,
          aiDenoise: AiDenoiseParams(level: AiDenoiseLevel.medium),
        ),
        'everything',
      );
    });
  });
}
