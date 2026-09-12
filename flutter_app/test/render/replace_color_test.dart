import 'dart:typed_data';

import 'package:darkmoon/render/hsl.dart';
import 'package:darkmoon/render/replace_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nothing runs until a colour is picked, or with nothing to move', () {
    expect(const ReplaceColorParams(hue: 90).isIdentity, isTrue);
    expect(const ReplaceColorParams(picked: true).isIdentity, isTrue);
    expect(
      const ReplaceColorParams(picked: true, hue: 90, amount: 0).isIdentity,
      isTrue,
    );
    expect(const ReplaceColorParams(picked: true, hue: 90).isIdentity, isFalse);
    final values = {
      'ReplaceColorPicked': 1.0,
      'ReplaceColorR': 200.0,
      'ReplaceColorHue': 30.0,
      'ReplaceColorAmount': 100.0,
    };
    final p = ReplaceColorParams.fromValues(values);
    expect(p.r, 200);
    expect(p.g, 128);
    expect(p.hue, 30);
    expect(p.isIdentity, isFalse);
  });

  test('the weight is full inside the range, a ramp across the softness', () {
    expect(replaceColorWeight(10, 30, 20), 1.0);
    expect(replaceColorWeight(30, 30, 20), 1.0);
    expect(replaceColorWeight(40, 30, 20), closeTo(0.5, 1e-9));
    expect(replaceColorWeight(50, 30, 20), 0.0);
    expect(replaceColorWeight(31, 30, 0), 0.0);
  });

  test('a picked red turns green at full amount, neighbours untouched', () {
    // Pixel 0: the picked red. Pixel 1: a far-away blue. Pixel 2: a red a
    // little off the pick, inside the softness ramp.
    final buffer = Float32List.fromList([
      220, 30, 30, //
      20, 40, 230, //
      220, 30, 110, //
    ]);
    const p = ReplaceColorParams(
      picked: true,
      r: 220,
      g: 30,
      b: 30,
      tolerance: 10, // core 30
      feather: 50, // ramp 75
      hue: 120,
      amount: 100,
    );
    applyReplaceColor(buffer, p);
    final (h0, _, _) = rgbToHsv(
      buffer[0] / 255,
      buffer[1] / 255,
      buffer[2] / 255,
    );
    expect(h0, closeTo(120, 0.5));
    expect(buffer.sublist(3, 6), [20, 40, 230]);
    // 80 away: past the core by 50 of a 75 ramp, so partly moved.
    expect(buffer[6], lessThan(220));
    expect(buffer[6], greaterThan(30));
  });

  test('amount blends the change, saturation and luminance scale', () {
    final full = Float32List.fromList([200, 100, 50]);
    final half = Float32List.fromList([200, 100, 50]);
    const base = ReplaceColorParams(
      picked: true,
      r: 200,
      g: 100,
      b: 50,
      saturation: -100,
      luminance: -50,
    );
    applyReplaceColor(
      full,
      const ReplaceColorParams(
        picked: true,
        r: 200,
        g: 100,
        b: 50,
        saturation: -100,
        luminance: -50,
        amount: 100,
      ),
    );
    applyReplaceColor(half, base.copyWithAmount(50));
    // Saturation -100 makes it grey; luminance -50 halves the value.
    expect(full[0], closeTo(100, 1));
    expect(full[1], closeTo(100, 1));
    expect(full[2], closeTo(100, 1));
    expect(half[0], closeTo(150, 1));
    expect(half[2], closeTo(75, 1));
  });
}

extension on ReplaceColorParams {
  ReplaceColorParams copyWithAmount(double amount) => ReplaceColorParams(
    picked: picked,
    r: r,
    g: g,
    b: b,
    tolerance: tolerance,
    feather: feather,
    hue: hue,
    saturation: saturation,
    luminance: luminance,
    amount: amount,
  );
}
