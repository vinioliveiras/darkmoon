import 'package:darkmoon/presets/preset.dart';
import 'package:darkmoon/presets/preset_xmp.dart';
import 'package:darkmoon/render/tone_curve.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preset round-trips through XMP unchanged', () {
    final original = Preset(
      id: 'preset_1',
      name: 'My Preset',
      values: {
        'Temperature': 6500,
        'Tint': 12,
        'Exposure': 40,
        'Contrast': -20,
        'Highlights': -30,
        'Shadows': 25,
        'Whites': 10,
        'Blacks': -10,
        'Texture': 15,
        'Clarity': 20,
        'Dehaze': 5,
        'Vibrance': 30,
        'Saturation': -5,
        'DenoiseLuminance': 40,
        'DenoiseColor': 25,
        'MixerRedHue': 10,
        'MixerRedSaturation': -20,
        'MixerRedLuminance': 5,
        'GradeShadowsHue': 210,
        'GradeShadowsSaturation': 15,
        'GradeShadowsLuminance': -5,
      },
      curves: const PhotoCurves(
        tone: [CurvePoint(0, 0), CurvePoint(0.5, 0.6), CurvePoint(1, 1)],
        red: [CurvePoint(0, 0.1), CurvePoint(1, 0.9)],
      ),
    );

    final xml = xmpFromPreset(original);
    final decoded = presetFromXmp(xml, fallbackName: 'fallback');

    expect(decoded, isNotNull);
    expect(decoded!.name, 'My Preset');
    for (final entry in original.values.entries) {
      expect(
        decoded.values[entry.key],
        closeTo(entry.value, 0.5),
        reason: 'mismatch for ${entry.key}',
      );
    }
    expect(decoded.curves.tone.length, original.curves.tone.length);
    for (var i = 0; i < original.curves.tone.length; i++) {
      expect(
        decoded.curves.tone[i].x,
        closeTo(original.curves.tone[i].x, 0.01),
      );
      expect(
        decoded.curves.tone[i].y,
        closeTo(original.curves.tone[i].y, 0.01),
      );
    }
    expect(decoded.curves.red.length, original.curves.red.length);
  });

  test('identity curve is omitted from the XMP and re-read as identity', () {
    const preset = Preset(id: 'p', name: 'Neutral', values: {});
    final xml = xmpFromPreset(preset);
    final decoded = presetFromXmp(xml, fallbackName: 'fallback');
    expect(decoded, isNotNull);
    expect(isIdentityToneCurve(decoded!.curves.tone), isTrue);
  });

  test('non-XMP input is rejected rather than throwing', () {
    expect(presetFromXmp('not xml at all', fallbackName: 'x'), isNull);
    expect(presetFromXmp('<html></html>', fallbackName: 'x'), isNull);
  });
}
