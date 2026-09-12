import 'dart:convert';
import 'dart:typed_data';

import 'package:darkmoon/catalog/removal.dart';
import 'package:flutter_test/flutter_test.dart';

/// A removal's coverage survives the trip through PNG and JSON, grows by
/// the pixels asked for, and resamples both ways.
void main() {
  Float32List disc(int width, int height) {
    final alpha = Float32List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final dx = x - width / 2, dy = y - height / 2;
        alpha[y * width + x] = dx * dx + dy * dy < 100 ? 1.0 : 0.0;
      }
    }
    return alpha;
  }

  test('the coverage comes back from PNG and from JSON', () {
    const w = 40, h = 30;
    final alpha = disc(w, h);
    alpha[5] = 0.5;
    final png = encodeAlphaPng(alpha, w, h);
    final back = decodeAlphaPng(png)!;
    expect(back.width, w);
    expect(back.height, h);
    for (var i = 0; i < alpha.length; i++) {
      expect(back.alpha[i], closeTo(alpha[i], 1 / 255));
    }
    final removal = Removal(
      name: 'Removal 1',
      width: w,
      height: h,
      alphaPng: png,
    );
    final json = removal.toJson();
    final parsed = Removal.fromJson(json)!;
    expect(parsed.name, 'Removal 1');
    expect(parsed.visible, isTrue);
    expect(parsed.signature, removal.signature);
    expect(parsed.copyWith(visible: false).visible, isFalse);
    expect(Removal.fromJson([1, 2, 3]), isNull);
    expect(Removal.fromJson({'name': 'x'}), isNull);
  });

  test('growing pushes the edge out by the radius', () {
    const w = 40, h = 30;
    final alpha = disc(w, h);
    final grown = dilateAlpha(alpha, w, h, 3);
    // Just outside the disc before, inside after.
    expect(alpha[15 * w + 32], 0.0);
    expect(grown[15 * w + 32], 1.0);
    // Well outside stays outside.
    expect(grown[15 * w + 36], 0.0);
    expect(identical(dilateAlpha(alpha, w, h, 0), alpha), isTrue);
  });

  test('resampling keeps the disc where it was', () {
    const w = 40, h = 30;
    final alpha = disc(w, h);
    final small = resampleAlpha(alpha, w, h, 20, 15);
    expect(small[7 * 20 + 10], 1.0);
    expect(small[0], 0.0);
    final big = resampleAlpha(small, 20, 15, 80, 60);
    expect(big[30 * 80 + 40], closeTo(1.0, 0.01));
    expect(big[2 * 80 + 2], 0.0);
    expect(identical(resampleAlpha(alpha, w, h, w, h), alpha), isTrue);
  });

  test('the fill mode and its source or patch survive JSON', () {
    final alpha = encodeAlphaPng(Float32List(16), 4, 4);
    final clone = Removal(
      name: 'c',
      width: 4,
      height: 4,
      alphaPng: alpha,
      mode: RemovalMode.heal,
      sourceDx: 0.25,
      sourceDy: -0.1,
    );
    final back = Removal.fromJson(jsonDecode(jsonEncode(clone.toJson())))!;
    expect(back.mode, RemovalMode.heal);
    expect(back.sourceDx, 0.25);
    expect(back.sourceDy, -0.1);
    final ai = Removal(name: 'a', width: 4, height: 4, alphaPng: alpha);
    expect(
      Removal.fromJson(jsonDecode(jsonEncode(ai.toJson())))!.mode,
      RemovalMode.ai,
    );
    // Same coverage, different fill: different result, different key.
    expect(clone.signature, isNot(ai.signature));
    expect(
      clone.copyWith(name: 'x').signature,
      Removal(
        name: 'y',
        width: 4,
        height: 4,
        alphaPng: alpha,
        mode: RemovalMode.heal,
        sourceDx: 0.25,
        sourceDy: -0.1,
      ).signature,
    );
    final generative = Removal(
      name: 'g',
      width: 4,
      height: 4,
      alphaPng: alpha,
      mode: RemovalMode.generative,
      patchPng: Uint8List.fromList([1, 2, 3]),
      patchLeft: 0.1,
      patchTop: 0.2,
      patchWidth: 0.3,
      patchHeight: 0.4,
    );
    final g = Removal.fromJson(jsonDecode(jsonEncode(generative.toJson())))!;
    expect(g.mode, RemovalMode.generative);
    expect(g.patchPng, [1, 2, 3]);
    expect(g.patchWidth, 0.3);
    expect(g.signature, isNot(ai.signature));
  });
}
