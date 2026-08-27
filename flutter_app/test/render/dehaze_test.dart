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

  // Expected values below were computed from RapidRAW's apply_dehaze
  // (shader.wgsl) via a reference Python port — fixed atmospheric light,
  // per-pixel + sigma-40-regional dark channel with halo protection,
  // shadow lift, saturation boost — independent of dehaze.dart's own
  // implementation.

  test('haze removal (positive amount) darkens and adds contrast', () {
    final source = _syntheticHazyPhoto(6, 6);
    final buffer = _toBuffer(source);
    applyDehaze(buffer, 6, 6, 60);
    final result = _toUint8(buffer);

    expect(result[0], closeTo(0, 1));
    expect(result[1], closeTo(32, 1));
    expect(result[2], closeTo(51, 1));

    expect(result[21], closeTo(0, 1));
    expect(result[22], closeTo(0, 1));
    expect(result[23], closeTo(46, 1));

    expect(result[105], closeTo(176, 1));
    expect(result[106], closeTo(197, 1));
    expect(result[107], closeTo(215, 1));
  });

  test('haze addition (negative amount) lightens toward atmospheric light', () {
    final source = _syntheticHazyPhoto(6, 6);
    final buffer = _toBuffer(source);
    applyDehaze(buffer, 6, 6, -50);
    final result = _toUint8(buffer);

    expect(result[0], closeTo(140, 1));
    expect(result[1], closeTo(144, 1));
    expect(result[2], closeTo(149, 1));

    expect(result[105], closeTo(220, 1));
    expect(result[106], closeTo(228, 1));
    expect(result[107], closeTo(236, 1));
  });
}
