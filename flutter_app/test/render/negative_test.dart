import 'dart:typed_data';

import 'package:darkmoon/render/negative.dart';
import 'package:flutter_test/flutter_test.dart';

/// A synthetic colour negative: a horizontal grey ramp under an orange
/// mask, dark where the scene was bright.
Uint8List _negativeRamp(int width, int height) {
  final bytes = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 3;
      final scene = x / (width - 1); // 0 = black scene, 1 = white scene
      final neg = 1 - scene;
      // Orange mask: red passes most, blue least.
      bytes[i] = (40 + neg * 200).round().clamp(0, 255);
      bytes[i + 1] = (25 + neg * 170).round().clamp(0, 255);
      bytes[i + 2] = (15 + neg * 120).round().clamp(0, 255);
    }
  }
  return bytes;
}

Float32List _asBuffer(Uint8List rgb) =>
    Float32List.fromList([for (final v in rgb) v.toDouble()]);

void main() {
  const width = 200, height = 60;
  final negative = _negativeRamp(width, height);
  final bounds = analyzeNegativeBounds(negative, width, height);

  test('bounds span the density of the frame, per channel', () {
    for (var c = 0; c < 3; c++) {
      expect(bounds.max[c], greaterThan(bounds.min[c] + 0.5), reason: 'ch $c');
    }
    // The mask makes blue the densest channel: its range sits highest.
    expect(bounds.min[2], greaterThan(bounds.min[0]));
  });

  test('disabled params leave the buffer untouched', () {
    final buffer = _asBuffer(negative);
    final before = Float32List.fromList(buffer);
    applyNegative(buffer, const NegativeParams(), bounds);
    expect(buffer, before);
  });

  test('inverting brings the bright scene edge up and the dark one down', () {
    final buffer = _asBuffer(negative);
    applyNegative(buffer, const NegativeParams(enabled: true), bounds);
    double luma(int x) {
      final i = (height ~/ 2 * width + x) * 3;
      return 0.2126 * buffer[i] +
          0.7152 * buffer[i + 1] +
          0.0722 * buffer[i + 2];
    }

    expect(luma(width - 1), greaterThan(220));
    expect(luma(0), lessThan(35));
    expect(luma(width ~/ 2), greaterThan(luma(0)));
    expect(luma(width ~/ 2), lessThan(luma(width - 1)));
    // The mask is neutralised: a mid-grey scene comes out close to grey.
    final i = (height ~/ 2 * width + width ~/ 2) * 3;
    final spread =
        [
          buffer[i],
          buffer[i + 1],
          buffer[i + 2],
        ].reduce((a, b) => a > b ? a : b) -
        [
          buffer[i],
          buffer[i + 1],
          buffer[i + 2],
        ].reduce((a, b) => a < b ? a : b);
    expect(spread, lessThan(20));
  });

  test('exposure brightens, contrast steepens, weights tint', () {
    final base = _asBuffer(negative);
    applyNegative(base, const NegativeParams(enabled: true), bounds);
    final bright = _asBuffer(negative);
    applyNegative(
      bright,
      const NegativeParams(enabled: true, exposure: 0.5),
      bounds,
    );
    final i = (height ~/ 2 * width + width ~/ 2) * 3;
    expect(bright[i + 1], greaterThan(base[i + 1]));

    final steep = _asBuffer(negative);
    applyNegative(
      steep,
      const NegativeParams(enabled: true, contrast: 2.0),
      bounds,
    );
    final lo = (height ~/ 2 * width + width ~/ 4) * 3;
    final hi = (height ~/ 2 * width + width * 3 ~/ 4) * 3;
    expect(
      steep[hi + 1] - steep[lo + 1],
      greaterThan(base[hi + 1] - base[lo + 1]),
    );

    final warm = _asBuffer(negative);
    applyNegative(
      warm,
      const NegativeParams(enabled: true, redWeight: 1.2),
      bounds,
    );
    expect(warm[i] - warm[i + 2], greaterThan(base[i] - base[i + 2]));
  });

  test('fromValues reads the section switch and its sliders', () {
    final p = NegativeParams.fromValues({
      'Negative': 1,
      'NegativeRed': 1.1,
      'NegativeBlue': 0.9,
      'NegativeExposure': -0.3,
      'NegativeContrast': 1.4,
    });
    expect(p.enabled, isTrue);
    expect(p.redWeight, 1.1);
    expect(p.greenWeight, 1.0);
    expect(p.blueWeight, 0.9);
    expect(p.exposure, -0.3);
    expect(p.contrast, 1.4);
    expect(NegativeParams.fromValues({}).enabled, isFalse);
  });

  test('the curve is pinned at 0 and 1', () {
    for (final p in [
      const NegativeParams(),
      const NegativeParams(exposure: 0.8, contrast: 1.8),
      const NegativeParams(exposure: -0.8, contrast: 0.6),
    ]) {
      final c = p.curve;
      double f(double x) =>
          (1 / (1 + _exp(-c.k * (x - c.x0))) - c.y0) * c.scale;
      expect(f(0), closeTo(0, 1e-9));
      expect(f(1), closeTo(1, 1e-9));
    }
  });
}

double _exp(double v) => _e(v);
double _e(double v) {
  // dart:math's exp, kept out of the test's import list on purpose so
  // the pinning check does not share a helper with the code it checks.
  var sum = 1.0, term = 1.0;
  for (var n = 1; n < 60; n++) {
    term *= v / n;
    sum += term;
  }
  return sum;
}
