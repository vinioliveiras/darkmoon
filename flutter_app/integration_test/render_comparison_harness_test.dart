// Item 7 of the Solstice-parity plan: a comprehensive CPU/GPU comparison
// harness covering every adjustment ported from Solstice this session
// (Vibrance/Saturation, Color Mixer including Luminance, Dehaze, White
// Balance, Tone/Color Curves), individually and combined, on one fixed
// synthetic image — see support/render_comparison_harness.dart's own doc
// comment for exactly what this can and can't compare (CPU vs. this app's
// own GPU path; not a direct Solstice-binary comparison).
//
// Run with: flutter test integration_test/render_comparison_harness_test.dart -d windows
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:darkmoon/render/color_mixer.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/tone_curve.dart';

import 'support/render_comparison_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const width = 180;
  const height = 120;
  final photo = buildComparisonHarnessPhoto(width, height);

  Future<void> runCase(
    String label,
    RenderParams params, {
    double maxMeanDiff = 6.0,
    int maxMaxDiff = 32,
    double maxDivergentFraction = 0.20,
  }) async {
    testWidgets(label, (tester) async {
      final result = await compareRenderers(width, height, photo, params);
      // ignore: avoid_print
      print('[render_comparison_harness] $label: $result');
      expect(
        result.meanDiff,
        lessThan(maxMeanDiff),
        reason: '$label: mean diff ${result.meanDiff}',
      );
      expect(
        result.maxDiff,
        lessThan(maxMaxDiff),
        reason: '$label: max diff ${result.maxDiff}',
      );
      expect(
        result.divergentFraction,
        lessThan(maxDivergentFraction),
        reason:
            '$label: ${result.divergentPixelBytes}/${result.totalBytes} '
            'bytes diverge beyond tolerance ${result.tolerance}',
      );
    });
  }

  group('render comparison harness (CPU vs GPU, tolerance=1)', () {
    runCase('neutral params', const RenderParams());

    runCase(
      'exposure + brightness + contrast',
      const RenderParams(exposure: 25, brightness: -15, contrast: 20),
    );

    runCase(
      'highlights + shadows + whites + blacks',
      const RenderParams(highlights: -30, shadows: 35, whites: 15, blacks: -15),
    );

    runCase(
      'white balance: warm shift + magenta tint',
      const RenderParams(temperature: 7500, tint: 25),
    );

    runCase(
      'white balance: cool shift + green tint',
      const RenderParams(temperature: 3500, tint: -25),
    );

    runCase('dehaze removal', const RenderParams(dehaze: 60));

    runCase('dehaze addition', const RenderParams(dehaze: -50));

    runCase(
      'saturation then vibrance',
      const RenderParams(saturation: 30, vibrance: 40),
    );

    runCase(
      'saturation then vibrance (reduce both)',
      const RenderParams(saturation: -40, vibrance: -30),
    );

    runCase(
      'color mixer: hue + saturation across several bands',
      const RenderParams(
        colorMixer: ColorMixerValues(
          red: ChannelAdjust(hue: 20, saturation: 30),
          blue: ChannelAdjust(hue: -15, saturation: 40),
          green: ChannelAdjust(saturation: -25),
        ),
      ),
    );

    runCase(
      'color mixer: luminance across several bands',
      const RenderParams(
        colorMixer: ColorMixerValues(
          red: ChannelAdjust(luminance: 40),
          blue: ChannelAdjust(luminance: -40),
          orange: ChannelAdjust(luminance: 25),
        ),
      ),
    );

    runCase(
      'tone curve (S-curve) + color curves',
      RenderParams(
        curves: PhotoCurves(
          tone: const [
            CurvePoint(0, 0),
            CurvePoint(0.25, 0.15),
            CurvePoint(0.75, 0.85),
            CurvePoint(1, 1),
          ],
          red: const [CurvePoint(0, 0), CurvePoint(1, 0.9)],
        ),
      ),
    );

    runCase(
      'everything ported this session, combined',
      RenderParams(
        temperature: 6800,
        tint: 15,
        exposure: 15,
        brightness: 10,
        contrast: 15,
        highlights: -20,
        shadows: 25,
        whites: 10,
        blacks: -10,
        dehaze: 30,
        vibrance: 25,
        saturation: 15,
        colorMixer: const ColorMixerValues(
          red: ChannelAdjust(hue: 10, saturation: 15, luminance: -10),
          blue: ChannelAdjust(hue: -10, saturation: 20, luminance: 10),
        ),
        curves: PhotoCurves(
          tone: const [
            CurvePoint(0, 0),
            CurvePoint(0.5, 0.55),
            CurvePoint(1, 1),
          ],
        ),
      ),
      // Everything active at once compounds each stage's own GPU/CPU
      // rounding noise the furthest — same reasoning as
      // gpu_full_pipeline_test.dart's own "everything active" case.
      maxMeanDiff: 8.0,
      maxMaxDiff: 45,
      maxDivergentFraction: 0.30,
    );
  });
}
