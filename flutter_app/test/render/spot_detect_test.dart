import 'dart:typed_data';

import 'package:darkmoon/render/spot_detect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finds dust spots and a thin scratch, leaves objects alone', () {
    const w = 200, h = 150;
    final rgb = Uint8List(w * h * 3);
    // A smooth gradient with soft texture.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 3;
        final v = 60 + (x * 120) ~/ w + ((x + y) % 7);
        rgb[i] = v;
        rgb[i + 1] = v + 10;
        rgb[i + 2] = v + 20;
      }
    }
    void paint(int x, int y, int delta) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final i = (y * w + x) * 3;
      for (var c = 0; c < 3; c++) {
        rgb[i + c] = (rgb[i + c] + delta).clamp(0, 255);
      }
    }

    // Three dust spots (3x3, 3x3, 1x2 — a lone pixel is noise, not dust).
    final spots = <(int, int)>[];
    paint(170, 20, 90);
    paint(171, 20, 90);
    spots.addAll([(170, 20), (171, 20)]);
    for (final (cx, cy, r) in [(30, 40, 1), (120, 90, 1)]) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          paint(cx + dx, cy + dy, 90);
          spots.add((cx + dx, cy + dy));
        }
      }
    }
    // A thin diagonal scratch, 40 px long.
    final scratch = <(int, int)>[];
    for (var k = 0; k < 40; k++) {
      paint(60 + k, 100 + k ~/ 3, -80);
      scratch.add((60 + k, 100 + k ~/ 3));
    }
    // A real object: a 30x30 square.
    for (var y = 30; y < 60; y++) {
      for (var x = 130; x < 160; x++) {
        paint(x, y, 90);
      }
    }

    final found = detectBlemishes(rgb, w, h, sensitivity: 0.5);
    expect(found.count, 4);
    int covered(List<(int, int)> pts) =>
        pts.where((p) => found.alpha[p.$2 * w + p.$1] > 0).length;
    expect(covered(spots), spots.length);
    expect(covered(scratch), greaterThan(scratch.length * 0.9));
    // The square's interior stays out (its edge is not a blemish either).
    var inSquare = 0;
    for (var y = 34; y < 56; y++) {
      for (var x = 134; x < 156; x++) {
        if (found.alpha[y * w + x] > 0) inSquare++;
      }
    }
    expect(inSquare, 0);
    // And the clean gradient is essentially untouched: the alpha covers
    // the blemishes plus their 2 px growth and nothing else.
    var total = 0;
    for (final a in found.alpha) {
      if (a > 0) total++;
    }
    expect(total, lessThan(900));
  });

  test('a flat clean frame yields nothing', () {
    const w = 64, h = 48;
    final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 120);
    final found = detectBlemishes(rgb, w, h, sensitivity: 1.0);
    expect(found.count, 0);
    expect(found.alpha.any((a) => a > 0), isFalse);
  });
}
