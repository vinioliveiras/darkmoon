import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/dehaze.dart';

/// A small hazy-looking synthetic photo — same shape as the one
/// `integration_test/gpu_dehaze_test.dart` uses, just smaller (so the
/// sigma-40 regional blur's edge-clamping dominates, keeping the reference
/// Python computation this test's expected values came from tractable).
Uint8List _syntheticHazyPhoto(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final edge = (x + y) % 2 == 0 ? 20 : 0;
      final haze = ((x + y) * 60) ~/ (width + height);
      bytes[i] = ((x * 120) ~/ width + edge + 40 + haze).clamp(0, 255);
      bytes[i + 1] = ((y * 120) ~/ height + edge + 50 + haze).clamp(0, 255);
      bytes[i + 2] = (((x + y) * 120) ~/ (width + height) + edge + 60 + haze)
          .clamp(0, 255);
    }
  }
  return bytes;
}

Float32List _toBuffer(Uint8List src) {
  final buffer = Float32List(src.length);
  for (var i = 0; i < src.length; i++) {
    buffer[i] = src[i].toDouble();
  }
  return buffer;
}

Uint8List _toUint8(Float32List buffer) {
  final out = Uint8List(buffer.length);
  for (var i = 0; i < buffer.length; i++) {
    out[i] = buffer[i].clamp(0.0, 255.0).round();
  }
  return out;
}

void main() {
  test('amount 0 is a no-op', () {
    final source = _syntheticHazyPhoto(6, 6);
    final buffer = _toBuffer(source);
    applyDehaze(buffer, 6, 6, 0);
    expect(_toUint8(buffer), source);
  });

  // The algorithm is Solstice's apply_dehaze (fixed atmospheric light,
  // per-pixel + sigma-40-regional dark channel with halo protection,
  // shadow lift, saturation boost), but the transmission/saturation
  // constants were recalibrated toward Meridian's feel (item 7 — see
  // dehaze.dart's `_dehaze*` constants), so exact reference values from
  // the original model no longer apply. These lock direction instead.

  test('haze removal (positive amount) darkens the hazy shadows', () {
    final source = _syntheticHazyPhoto(6, 6);
    final buffer = _toBuffer(source);
    applyDehaze(buffer, 6, 6, 60);
    final result = _toUint8(buffer);

    // Top-left is the haziest, darkest corner — dehaze pulls it down.
    expect(result[0], lessThan(source[0]));
    expect(result[1], lessThan(source[1]));
    expect(result[2], lessThan(source[2]));
  });

  test('haze addition (negative amount) lightens toward atmospheric light', () {
    final source = _syntheticHazyPhoto(6, 6);
    final buffer = _toBuffer(source);
    applyDehaze(buffer, 6, 6, -50);
    final result = _toUint8(buffer);

    expect(result[0], greaterThan(source[0]));
    expect(result[1], greaterThan(source[1]));
    expect(result[2], greaterThan(source[2]));
  });
}
