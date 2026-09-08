import 'package:darkmoon/editor_screen.dart';
import 'package:darkmoon/render/calibration.dart';
import 'package:flutter_test/flutter_test.dart';

/// The global Amount slider, and the per-key compression that goes with
/// it.
///
/// Two things here had gone wrong quietly and neither could fail loudly:
/// the compression map is an exact lookup, so a key spelled even slightly
/// wrong is simply never found; and the set of keys the slider walks came
/// from a map the Colour Mixer's and Colour Grading's runtime-built names
/// were never in, so the slider did nothing at all to either.
void main() {
  const amountKey = 'GlobalEditAmount';

  /// Everything the compression map can legitimately name: a real slider,
  /// or a family prefix for the runtime-built keys.
  const families = ['Mixer', 'Grade'];

  /// True when the Amount slider actually acts on [key].
  ///
  /// Detected by driving Amount to 0, where every key the slider reaches
  /// collapses to its own default and every key it does not reach comes
  /// back exactly as handed in. Enumerating the key set directly is not
  /// possible from here — the function returns only the keys it was
  /// given, so asking it for its whole vocabulary answers nothing.
  bool isReached(String key) {
    const probe = 999.0;
    final scaled = withGlobalEditAmountApplied({amountKey: 0.0, key: probe});
    return scaled[key] != probe;
  }

  test('no entry in the compression map is unreachable', () {
    // The guard for the whole class of bug. An entry that matches neither
    // a key nor a family is dead weight that reads as a working setting —
    // 'Shadow' sat here for a long time while the slider is 'Shadows',
    // and 'Sharpen' while the slider is 'SharpenAmount'.
    for (final key in calGlobalAmountCompressionOverrides.keys) {
      if (families.contains(key)) {
        continue;
      }
      expect(
        isReached(key),
        isTrue,
        reason:
            "'$key' is not a slider name, so this entry can never be found "
            'and silently does nothing',
      );
    }
  });

  test('each family prefix has members the slider reaches', () {
    expect(isReached('MixerRedHue'), isTrue);
    expect(isReached('GradeShadowsSaturation'), isTrue);
  });

  test('Amount reaches the Colour Mixer', () {
    const key = 'MixerRedHue';
    final full = withGlobalEditAmountApplied({amountKey: 100.0, key: 80.0});
    final half = withGlobalEditAmountApplied({amountKey: 50.0, key: 80.0});
    expect(
      half[key],
      lessThan(full[key]!),
      reason:
          'a preset whose look comes from the mixer used to ignore Amount '
          'outright',
    );
    expect(half[key], closeTo(full[key]! / 2, 0.001));
  });

  test('Amount reaches Colour Grading', () {
    const key = 'GradeShadowsSaturation';
    final full = withGlobalEditAmountApplied({amountKey: 100.0, key: 60.0});
    final half = withGlobalEditAmountApplied({amountKey: 50.0, key: 60.0});
    expect(half[key], closeTo(full[key]! / 2, 0.001));
  });

  test('neither family is damped at full Amount', () {
    // They were unreachable until now, so every saved preset assumes them
    // at full strength. Damping them would restyle the library.
    for (final key in const ['MixerRedHue', 'GradeShadowsSaturation']) {
      expect(
        withGlobalEditAmountApplied({amountKey: 100.0, key: 40.0})[key],
        closeTo(40.0, 0.001),
        reason: '$key must pass through untouched at Amount 100%',
      );
    }
  });

  test('an exact entry beats its family', () {
    expect(
      calGlobalAmountCompressionOverrides['Mixer'],
      isNotNull,
      reason: 'this test is about the family being the fallback, not the '
          'only source',
    );
    // Exposure has its own entry and no family, so it is the clean case
    // for "exact wins".
    final scaled = withGlobalEditAmountApplied({
      amountKey: 100.0,
      'Exposure': 1.0,
    });
    expect(
      scaled['Exposure'],
      closeTo(calGlobalAmountCompressionOverrides['Exposure']!, 0.001),
    );
  });

  test('Temperature and Tint are never scaled', () {
    // They are not 0-centred deltas, so scaling them toward a default
    // would fight the as-shot-relative white balance model.
    final scaled = withGlobalEditAmountApplied({
      amountKey: 10.0,
      'Temperature': 7000.0,
      'Tint': 12.0,
    });
    expect(scaled['Temperature'], 7000.0);
    expect(scaled['Tint'], 12.0);
  });
}
