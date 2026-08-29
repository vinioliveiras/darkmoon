import 'dart:typed_data';

import 'package:darkmoon/render/color_profile.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List _rgb(List<int> px) =>
    Float32List.fromList([for (final v in px) v.toDouble()]);

void main() {
  test('identity profile is a no-op', () {
    final buf = _rgb([200, 40, 40, 40, 180, 60, 30, 60, 200]);
    final before = Float32List.fromList(buf);
    applyColorProfile(buf, identityColorProfile, 1.0);
    for (var i = 0; i < buf.length; i++) {
      expect(buf[i], closeTo(before[i], 0.01));
    }
  });

  test('strength 0 is a no-op even with a real profile', () {
    final profile = ColorProfile(
      hueShift: List<double>.filled(colorProfileBins, 20),
      satMul: List<double>.filled(colorProfileBins, 1.5),
      lumMul: List<double>.filled(colorProfileBins, 1.2),
    );
    final buf = _rgb([200, 40, 40]);
    final before = Float32List.fromList(buf);
    applyColorProfile(buf, profile, 0.0);
    for (var i = 0; i < buf.length; i++) {
      expect(buf[i], closeTo(before[i], 0.01));
    }
  });

  test('a positive hue shift rotates a saturated pixel', () {
    // A pure-ish red (hue ~0) with +30° across the board -> toward orange:
    // green channel should rise.
    final profile = ColorProfile(
      hueShift: List<double>.filled(colorProfileBins, 30),
      satMul: List<double>.filled(colorProfileBins, 1),
      lumMul: List<double>.filled(colorProfileBins, 1),
    );
    final buf = _rgb([200, 30, 30]);
    applyColorProfile(buf, profile, 1.0);
    expect(buf[1], greaterThan(30));
  });

  test('a near-grey pixel is left alone (hue is noise there)', () {
    final profile = ColorProfile(
      hueShift: List<double>.filled(colorProfileBins, 40),
      satMul: List<double>.filled(colorProfileBins, 2),
      lumMul: List<double>.filled(colorProfileBins, 1),
    );
    final buf = _rgb([128, 129, 127]);
    final before = Float32List.fromList(buf);
    applyColorProfile(buf, profile, 1.0);
    for (var i = 0; i < buf.length; i++) {
      expect(buf[i], closeTo(before[i], 1.0));
    }
  });

  test('JSON round-trips', () {
    final profile = ColorProfile(
      hueShift: [for (var i = 0; i < colorProfileBins; i++) i.toDouble()],
      satMul: List<double>.filled(colorProfileBins, 1.1),
      lumMul: List<double>.filled(colorProfileBins, 0.95),
      name: 'test',
    );
    final decoded = ColorProfile.decode(profile.encode());
    expect(decoded.name, 'test');
    expect(decoded.hueShift, profile.hueShift);
    expect(decoded.satMul, profile.satMul);
    expect(decoded.lumMul, profile.lumMul);
  });
}
