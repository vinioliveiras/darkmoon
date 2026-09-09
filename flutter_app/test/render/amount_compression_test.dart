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

  /// One real slider key per family, for the family-fallback checks.
  /// 'GradeRedHue' is not a grading slider — the grading keys are
  /// GradeShadowsSaturation and friends — and a made-up key falls outside
  /// the slider's reach entirely, which is not what a fallback test wants
  /// to measure.
  const familyMember = {
    'Mixer': 'MixerRedHue',
    'Grade': 'GradeShadowsSaturation',
  };

  test('at full Amount each family is scaled by its own entry, or passes '
      'through when it has none', () {
    // Whatever calibration.dart says the family factor is — 1.0 while the
    // families were left at full strength for the preset library, 0.5
    // since the 2026-09-09 recalibration — this reads it rather than
    // pinning a number the tuning surface is meant to change.
    familyMember.forEach((family, key) {
      final factor = calGlobalAmountCompressionOverrides[family] ?? 1.0;
      expect(
        withGlobalEditAmountApplied({amountKey: 100.0, key: 40.0})[key],
        closeTo(40.0 * factor, 0.001),
        reason: "'$key' must follow the '$family' entry ($factor)",
      );
    });
  });

  test('every exact entry is the factor its own key is scaled by', () {
    // Deliberately over whatever the map happens to hold rather than over
    // a named key. calibration.dart is the user's tuning surface and its
    // entries get commented out during a round of tuning; this test used
    // to name 'Exposure' and started throwing on a null the moment that
    // happened, which says nothing about the code under test.
    final exact = calGlobalAmountCompressionOverrides.keys
        .where((key) => !families.contains(key))
        .toList();
    expect(
      exact,
      isNotEmpty,
      reason:
          'with no exact entries left there is nothing here to check '
          '— the global factor alone is covered elsewhere',
    );
    for (final key in exact) {
      expect(
        withGlobalEditAmountApplied({amountKey: 100.0, key: 1.0})[key],
        closeTo(calGlobalAmountCompressionOverrides[key]!, 0.001),
        reason:
            "'$key' must be scaled by its own entry, not the global "
            'default',
      );
    }
  });

  test('a family entry applies to keys that have no exact one', () {
    // The other half: a family name is a prefix, not a slider, and every
    // MixerRedHue-shaped key falls back to it. Skipped rather than pinned
    // when the family has no entry — calibration.dart is a tuning surface
    // and its entries get commented out; a test that names one keeps
    // failing on edits that are not bugs.
    for (final family in families) {
      final compression = calGlobalAmountCompressionOverrides[family];
      if (compression == null) {
        continue;
      }
      final key = familyMember[family]!;
      expect(
        withGlobalEditAmountApplied({amountKey: 100.0, key: 1.0})[key],
        closeTo(compression, 0.001),
        reason: "'$key' should fall back to the '$family' family",
      );
    }
  });

  test('a shape parameter is never scaled, only an amount is', () {
    // The Amount slider answers "how much of this edit". A radius, a
    // midpoint, a feather, a grain size are not edits with a size — they
    // are the shape the edit takes, and scaling one toward its default has
    // no meaning. Sharpen showed why this matters: SharpenAmount passed
    // through untouched while SharpenRadius was pulled from 3.0 to 1.6, so
    // the amount was honoured and the shape it applied at was not
    // (2026-09-09).
    //
    // Each entry is the slider's own default; the probe pushes it ten past
    // that and checks the whole ten survives.
    const shape = <String, double>{
      'SharpenRadius': 1.0,
      'SharpenDetail': 25,
      'SharpenMasking': 0,
      'VignetteMidpoint': 50,
      'VignetteFeather': 50,
      'GrainSize': 25,
      'GrainRoughness': 50,
    };
    shape.forEach((key, base) {
      expect(
        withGlobalEditAmountApplied({amountKey: 100.0, key: base + 10})[key],
        closeTo(base + 10, 0.001),
        reason: "'$key' describes the shape of an effect, not its size",
      );
    });
  });

  test('an amount still is', () {
    // The other side of the same rule, so "protect the shape parameters"
    // cannot quietly become "protect everything": these two are what the
    // Amount slider is for. Checked at half Amount, not full: whether an
    // amount is *damped* at 100% is calibration.dart's call (the global
    // fraction has been 0.3 and is 1.0 today); whether the slider reaches
    // it at all is the rule this test protects.
    for (final key in const ['VignetteAmount', 'GrainAmount']) {
      final full = withGlobalEditAmountApplied({
        amountKey: 100.0,
        key: 100.0,
      })[key]!;
      final half = withGlobalEditAmountApplied({
        amountKey: 50.0,
        key: 100.0,
      })[key]!;
      expect(
        half,
        lessThan(full),
        reason: "'$key' is an amount and has to scale with Amount",
      );
      expect(half, closeTo(full / 2, 0.001));
    }
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
