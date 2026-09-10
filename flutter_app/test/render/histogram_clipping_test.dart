import 'dart:typed_data';

import 'package:darkmoon/render/histogram.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('counts clipped pixels per channel at both ends', () {
    // 10 pixels: 2 with red blown, 1 with every channel blown, 3 with blue
    // crushed, the rest mid-grey.
    final rgb = Uint8List.fromList([
      255, 120, 120, //
      254, 120, 120, //
      255, 255, 254, //
      120, 120, 0, //
      120, 120, 1, //
      120, 120, 1, //
      128, 128, 128, //
      128, 128, 128, //
      128, 128, 128, //
      128, 128, 128, //
    ]);
    final h = computeHistogram(rgb);
    expect(h.pixelCount, 10);
    expect(h.clippedHigh, [3, 1, 1]);
    expect(h.clippedLow, [0, 0, 3]);
    expect(h.clippedHighFraction(0), closeTo(0.3, 1e-9));
    expect(h.clippedLowFraction(2), closeTo(0.3, 1e-9));
    expect(h.clippedHighFraction(1), closeTo(0.1, 1e-9));
  });

  test('RGBA input skips alpha and counts the same', () {
    final rgba = Uint8List.fromList([255, 0, 128, 255, 10, 255, 128, 255]);
    final h = computeHistogram(rgba, channels: 4);
    expect(h.pixelCount, 2);
    expect(h.clippedHigh, [1, 1, 0]);
    expect(h.clippedLow, [0, 1, 0]);
  });

  test('a histogram without counts reports no clipping', () {
    const h = Histogram(red: [1], green: [1], blue: [1]);
    expect(h.clippedHighFraction(0), 0);
    expect(h.clippedLowFraction(2), 0);
  });
}
