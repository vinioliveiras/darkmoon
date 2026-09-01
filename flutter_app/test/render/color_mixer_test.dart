import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

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

    expect(result[0], closeTo(236, 1));
    expect(result[1], closeTo(0, 1));
    expect(result[2], closeTo(0, 1));
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

    // Re-derived 2026-09-01 after calMixerHueStrength eased back from 1.15
    // toward Solstice's original 0.6 (now 1.0) — every channel shifts with
    // the hue rotation strength, not just the two that moved the most.
    expect(result[0], closeTo(166, 1));
    expect(result[1], closeTo(0, 1));
    expect(result[2], closeTo(197, 1));
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

    expect(result[0], closeTo(136, 1));
    expect(result[1], closeTo(170, 1));
    expect(result[2], closeTo(204, 1));
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

    expect(result[0], closeTo(100, 1));
    expect(result[1], closeTo(126, 1));
    expect(result[2], closeTo(151, 1));
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
