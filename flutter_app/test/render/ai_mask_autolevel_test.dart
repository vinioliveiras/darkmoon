import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/native/ai_mask_models.dart';

/// A frame of [count] pixels whose channels all carry [value].
Uint8List gray(int count, int value) =>
    Uint8List(count * 3)..fillRange(0, count * 3, value);

/// A frame whose luma ramps across [values], one pixel per entry.
Uint8List ramp(List<int> values) {
  final out = Uint8List(values.length * 3);
  for (var i = 0; i < values.length; i++) {
    out[i * 3] = values[i];
    out[i * 3 + 1] = values[i];
    out[i * 3 + 2] = values[i];
  }
  return out;
}

void main() {
  group('autoLevelForAiMask', () {
    test('stretches a compressed range to fill 0..255', () {
      // A flat RAW: everything between 80 and 120, which is the shape the
      // models cope with worst.
      final input = ramp([for (var i = 0; i < 100; i++) 80 + (i * 40) ~/ 100]);
      final out = autoLevelForAiMask(input);
      expect(out.reduce((a, b) => a < b ? a : b), lessThan(20));
      expect(out.reduce((a, b) => a > b ? a : b), greaterThan(235));
    });

    test('barely moves a frame that already fills the range', () {
      // Not a no-op: percentiles clip 1% off each end by design, so a full
      // ramp comes back very slightly steeper. What matters is that it is
      // not *rearranged*.
      final input = ramp([for (var i = 0; i < 256; i++) i]);
      final out = autoLevelForAiMask(input);
      for (var i = 0; i < 256; i++) {
        expect((out[i * 3] - input[i * 3]).abs(), lessThan(4));
      }
    });

    test('leaves a flat frame alone rather than amplifying its noise', () {
      // Stretching this would turn a couple of levels of sensor noise into
      // full-contrast structure, which a segmentation model will happily
      // and confidently mis-read.
      final input = gray(64, 128);
      expect(autoLevelForAiMask(input), same(input));
    });

    test('applies one scale to all three channels, so no hue shifts', () {
      // A tinted mid-tone frame, kept well inside the range so the stretch
      // scales it rather than clipping it. A per-channel stretch would pull
      // the three channels apart by different amounts and white-balance the
      // photo as a side effect; a single scale keeps the gaps between them
      // in the proportion they went in with.
      final input = Uint8List(130 * 3);
      for (var i = 0; i < 130; i++) {
        final v = 60 + i;
        input[i * 3] = v;
        input[i * 3 + 1] = v - 10;
        input[i * 3 + 2] = v - 20;
      }
      final out = autoLevelForAiMask(input);

      // Read a pixel from the middle, where nothing is clipped at either end.
      const mid = 65;
      final gapHigh = out[mid * 3] - out[mid * 3 + 1];
      final gapLow = out[mid * 3 + 1] - out[mid * 3 + 2];
      expect(gapHigh, greaterThan(10), reason: 'the frame should open up');
      expect(gapLow, closeTo(gapHigh, 2));
    });

    test('ignores a 1% tail, so a few blown pixels cannot set the scale', () {
      // 99 mid-grey pixels and one blown white: the white must not become
      // the high anchor, or the stretch would be a no-op.
      final input = ramp([
        for (var i = 0; i < 99; i++) 100 + i ~/ 3,
        255,
      ]);
      final out = autoLevelForAiMask(input);
      expect(out.last, 255);
      // The real content still reached the top of the range.
      expect(out[3 * 98], greaterThan(200));
    });
  });
}
