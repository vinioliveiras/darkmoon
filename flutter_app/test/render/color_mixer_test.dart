import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/calibration.dart';
import 'package:darkmoon/render/color_mixer.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

void main() {
  test('identity mixer leaves the source unchanged', () {
    final source = Uint8List.fromList([50, 90, 200]);
    final result = renderRgb(1, 1, source, const RenderParams(baseContrast: 0));
    expect(result, source);
  });

  // Expected values below were computed from Solstice's apply_hsl_panel
  // (shader.wgsl) via a reference Python port — scene-linear HSV, per-band
  // Gaussian influence normalized per pixel, saturation-gated — independent
  // of color_mixer.dart's implementation. The hue-shift cases were
  // re-derived 2026-08-29 after `calMixerHueStrength` raised the per-unit
  // hue rotation from Solstice's 0.6 toward the Meridian Color Mixer;
  // saturation/luminance-only cases are unaffected.

  test('a saturation boost on a saturated pixel near a band center', () {
    final source = Uint8List.fromList([
      180,
      90,
      90,
    ]); // hue 0, close to Red's 358° center
    final result = renderRgb(
      1,
      1,
      source,
      const RenderParams(
        baseContrast: 0,
        colorMixer: ColorMixerValues(red: ChannelAdjust(saturation: 60)),
      ),
    );

    expect(result[0], closeTo(221, 1));
    expect(result[1], closeTo(49, 1));
    expect(result[2], closeTo(49, 1));
  });

  test('a hue+saturation push on a deep blue pixel', () {
    final source = Uint8List.fromList([
      50,
      90,
      200,
    ]); // hue ~232, near Blue's 225° center
    final result = renderRgb(
      1,
      1,
      source,
      const RenderParams(
        baseContrast: 0,
        colorMixer: ColorMixerValues(
          blue: ChannelAdjust(hue: 50, saturation: 40),
        ),
      ),
    );

    // Unlike every other case in this file, this one moves with
    // calMixerHueStrength, and re-deriving it independently needs the
    // Python port of Solstice's apply_hsl_panel referenced above — which
    // this repo doesn't carry. The numbers below were therefore re-captured
    // from the current implementation at calMixerHueStrength = 0.8, not
    // re-derived: treat this case as a regression pin on the hue path, not
    // as an independent check of it.
    //
    // The guard is what keeps that honest. This case was red on master
    // (asserting 166/0/197, derived when the constant was 1.0) because a
    // later tuning round moved the constant without touching the numbers;
    // failing on the constant itself says what to do about it, where a
    // bare byte mismatch did not.
    expect(
      calMixerHueStrength,
      0.8,
      reason:
          'calMixerHueStrength changed — the three expected bytes below '
          'were captured at 0.8 and are now stale. Re-capture them (and '
          'ideally re-derive them from the apply_hsl_panel reference) '
          'rather than widening the tolerance.',
    );
    expect(result[0], closeTo(159, 1));
    expect(result[1], closeTo(0, 1));
    expect(result[2], closeTo(213, 1));
  });

  test(
    'a low-saturation pixel is only partially affected (saturation gate)',
    () {
      final source = Uint8List.fromList([142, 145, 150]); // saturation ~0.113
      final result = renderRgb(
        1,
        1,
        source,
        const RenderParams(
          baseContrast: 0,
          colorMixer: ColorMixerValues(
            blue: ChannelAdjust(hue: 80, saturation: 80),
          ),
        ),
      );

      expect(result[0], closeTo(145, 1));
      expect(result[1], closeTo(144, 1));
      expect(result[2], closeTo(154, 1));
    },
  );

  test('a luminance boost brightens a pixel near a band center', () {
    final source = Uint8List.fromList([
      120,
      150,
      180,
    ]); // hue ~214, near Blue's 225° center
    final result = renderRgb(
      1,
      1,
      source,
      const RenderParams(
        baseContrast: 0,
        colorMixer: ColorMixerValues(blue: ChannelAdjust(luminance: 60)),
      ),
    );

    expect(result[0], closeTo(129, 1));
    expect(result[1], closeTo(161, 1));
    expect(result[2], closeTo(193, 1));
  });

  test('a luminance cut darkens a pixel near a band center', () {
    final source = Uint8List.fromList([120, 150, 180]);
    final result = renderRgb(
      1,
      1,
      source,
      const RenderParams(
        baseContrast: 0,
        colorMixer: ColorMixerValues(blue: ChannelAdjust(luminance: -60)),
      ),
    );

    expect(result[0], closeTo(111, 1));
    expect(result[1], closeTo(139, 1));
    expect(result[2], closeTo(167, 1));
  });

  test('a fully neutral gray pixel is left untouched', () {
    final source = Uint8List.fromList([128, 128, 128]);
    final result = renderRgb(
      1,
      1,
      source,
      const RenderParams(
        baseContrast: 0,
        colorMixer: ColorMixerValues(
          red: ChannelAdjust(hue: 50, saturation: 80),
          blue: ChannelAdjust(hue: -50, saturation: 80),
        ),
      ),
    );

    expect(result, source);
  });
}
