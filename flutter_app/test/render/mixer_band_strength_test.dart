import 'package:darkmoon/render/calibration.dart';
import 'package:darkmoon/render/color_mixer.dart';
import 'package:flutter_test/flutter_test.dart';

/// One band's sliders can be made gentler than the rest without touching
/// the other seven.
///
/// The scaling happens where the flat slider map becomes mixer values,
/// which is deliberately the single place both render paths read — the
/// GPU uploads these very numbers as its uMixer array. So checking it
/// here checks it for both, and there is no second copy to drift.
void main() {
  ColorMixerValues valuesWith(String band, double amount) =>
      ColorMixerValues.fromValues({
        'Mixer${band}Hue': amount,
        'Mixer${band}Saturation': amount,
        'Mixer${band}Luminance': amount,
      });

  test('every band defaults to untouched', () {
    for (final band in const [
      'Red',
      'Orange',
      'Yellow',
      'Green',
      'Aqua',
      'Blue',
      'Purple',
      'Magenta',
    ]) {
      expect(
        calMixerBandStrength[band],
        isNotNull,
        reason: '$band has no entry, so hand-editing it would silently do '
            'nothing',
      );
    }
    // Guards the assertions below, which are written against the shipped
    // defaults rather than against whatever the file currently holds.
    expect(
      calMixerBandStrength.values.every((v) => v == 1.0),
      isTrue,
      reason:
          'a band has been tuned away from 1.0 — that is what this knob is '
          'for, but the cases below assume the defaults, so retune them '
          'rather than widening anything',
    );
  });

  test('a band is scaled by its own entry', () {
    final orange = valuesWith('Orange', 50).orange;
    expect(orange.hue, 50 * (calMixerBandStrength['Orange'] ?? 1.0));
    expect(orange.saturation, 50 * (calMixerBandStrength['Orange'] ?? 1.0));
    expect(orange.luminance, 50 * (calMixerBandStrength['Orange'] ?? 1.0));
  });

  test('scaling one band leaves the others where they were', () {
    final mixed = ColorMixerValues.fromValues(const {
      'MixerOrangeHue': 40,
      'MixerBlueHue': 40,
    });
    expect(mixed.blue.hue, 40 * (calMixerBandStrength['Blue'] ?? 1.0));
    expect(
      mixed.orange.hue,
      40 * (calMixerBandStrength['Orange'] ?? 1.0),
      reason: 'the two bands must be scaled independently',
    );
  });

  test('an unset band is still identity', () {
    expect(ColorMixerValues.fromValues(const {}).isIdentity, isTrue);
  });
}
