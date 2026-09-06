import 'package:darkmoon/editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a photo's chosen colour profile survives a round trip through the
/// per-photo `Map<String, double>`.
///
/// This is the file to read before adding or removing a `ColorProfileMode`.
/// The enum has already been trimmed twice (2026-09-02), which left saved
/// photos carrying indices for modes that no longer exist, and the mapping
/// below is the only thing standing between those files and rendering as
/// whatever mode now happens to occupy that number.
void main() {
  Map<String, double> stored(double mode, {double id = 0}) => {
    colorProfileModeKey: mode,
    customProfileIdKey: id,
  };

  group('built-in modes', () {
    test('round-trip through the stored value', () {
      for (final mode in [
        ColorProfileMode.darkmoonDefault,
        ColorProfileMode.vivid,
      ]) {
        expect(
          colorProfileModeOf(stored(storedValueForColorProfileMode(mode))),
          mode,
        );
      }
    });

    test('an absent key reads as Default', () {
      expect(colorProfileModeOf(const {}), ColorProfileMode.darkmoonDefault);
    });
  });

  group('legacy indices from the removed modes', () {
    // The original enum was [default, vivid, goldenHour, tealOrange,
    // pastel, noir]. Round one removed goldenHour/tealOrange, shifting
    // pastel/noir down to 2/3; round two removed those too. Every one of
    // those numbers can still be sitting in someone's catalog.
    test('all fall back to Default, never to another mode', () {
      for (final legacy in [2.0, 3.0, 4.0, 5.0]) {
        expect(
          colorProfileModeOf(stored(legacy)),
          ColorProfileMode.darkmoonDefault,
          reason: 'stored index $legacy must not resolve to a live mode',
        );
      }
    });

    test('index 2 does not become the custom mode', () {
      // ColorProfileMode.custom sits at index 2, which is exactly the
      // number `pastel` was saved as. Storing custom by its index would
      // make every one of those old photos claim to use a user profile,
      // pointing at an id that never existed — which is why custom is
      // written as its own out-of-band value instead.
      expect(ColorProfileMode.custom.index, 2);
      expect(colorProfileModeOf(stored(2)), ColorProfileMode.darkmoonDefault);
    });
  });

  group('user profiles', () {
    test('custom is stored out of the index range', () {
      final value = storedValueForColorProfileMode(ColorProfileMode.custom);
      expect(value, customProfileStoredValue.toDouble());
      expect(
        value,
        greaterThan(ColorProfileMode.values.length.toDouble()),
        reason: 'it must not collide with any index this enum has ever had',
      );
    });

    test('round-trips together with the profile id', () {
      final values = stored(
        storedValueForColorProfileMode(ColorProfileMode.custom),
        id: 123456,
      );
      expect(colorProfileModeOf(values), ColorProfileMode.custom);
      expect(customProfileIdOf(values), 123456);
    });

    test('the id survives the trip through a double exactly', () {
      // Ids are 32-bit for this reason — see ColorProfile.id. The largest
      // one the generator can produce must come back unchanged.
      const largest = 0xFFFFFFFF - 1;
      expect(
        customProfileIdOf({customProfileIdKey: largest.toDouble()}),
        largest,
      );
    });
  });
}
