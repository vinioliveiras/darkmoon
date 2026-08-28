import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/grain.dart';

Float32List _flatMidGray(int width, int height) {
  final buf = Float32List(width * height * 3);
  for (var i = 0; i < buf.length; i++) {
    buf[i] = 128;
  }
  return buf;
}

double _variance(Float32List buf) {
  var mean = 0.0;
  for (final v in buf) {
    mean += v;
  }
  mean /= buf.length;
  var acc = 0.0;
  for (final v in buf) {
    acc += (v - mean) * (v - mean);
  }
  return acc / buf.length;
}

void main() {
  test('amount 0 is a no-op', () {
    final buf = _flatMidGray(16, 16);
    final before = Float32List.fromList(buf);
    applyGrain(buf, 16, 16, const GrainParams(amount: 0));
    expect(buf, before);
  });

  test('grain adds spatial noise to a flat patch', () {
    final buf = _flatMidGray(32, 32);
    expect(_variance(buf), 0);
    applyGrain(buf, 32, 32, const GrainParams(amount: 60));
    expect(_variance(buf), greaterThan(1.0));
  });

  test('grain is deterministic — same input, same output', () {
    final a = _flatMidGray(24, 24);
    final b = _flatMidGray(24, 24);
    applyGrain(a, 24, 24, const GrainParams(amount: 50, size: 30, roughness: 40));
    applyGrain(b, 24, 24, const GrainParams(amount: 50, size: 30, roughness: 40));
    expect(a, b);
  });

  test('more amount = more noise', () {
    final low = _flatMidGray(32, 32);
    final high = _flatMidGray(32, 32);
    applyGrain(low, 32, 32, const GrainParams(amount: 20));
    applyGrain(high, 32, 32, const GrainParams(amount: 90));
    expect(_variance(high), greaterThan(_variance(low)));
  });

  test('grain fades out of deep shadows', () {
    final black = Float32List(32 * 32 * 3); // all 0
    applyGrain(black, 32, 32, const GrainParams(amount: 90));
    expect(_variance(black), 0);
  });
}
