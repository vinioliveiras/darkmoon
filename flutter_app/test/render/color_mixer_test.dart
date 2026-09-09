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

    // Re-captured 2026-09-09, when calMixerBandNormalisation went to 0.
    // Dropping the per-pixel normalisation raises the response at a
    // band's centre — the old scheme divided by the sum of all eight
    // influences, so even a pixel sitting exactly on Red gave Red about
    // three quarters of the slider. It now gets all of it, which is why a
    // Saturation of 60 saturates this pixel fully.
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

    // Unlike every other case in this file, this one moves with
    // calMixerHueStrength, so it is pinned to that constant rather than
    // derived independently — re-deriving it needs the Python port of
    // Solstice's apply_hsl_panel referenced above, which this repo does
    // not carry.
    //
    // The guard is what keeps that honest, and it has now earned its keep
    // twice. The numbers were derived at 1.0, went stale when a tuning
    // round moved the constant to 0.8, and were re-captured there. Putting
    // the constant back to its documented default reproduces the original
    // three bytes exactly, which is a good sign they were right to begin
    // with.
    expect(
      calMixerHueStrength,
      1.0,
      reason:
          'calMixerHueStrength changed — the three expected bytes below '
          'go with 1.0 and are now stale. Re-capture them (and ideally '
          're-derive them from the apply_hsl_panel reference) rather than '
          'widening the tolerance.',
    );
    expect(result[0], closeTo(164, 1));
    expect(result[1], closeTo(0, 1));
    expect(result[2], closeTo(201, 1));
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
