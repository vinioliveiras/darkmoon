import 'dart:typed_data';

import 'package:darkmoon/render/tone_curve.dart';
import 'package:flutter_test/flutter_test.dart';

// The curve stack: parametric → point Tone Curve → per-channel colour
// curve, composed into one float LUT per channel and applied once with
// interpolation (2026-09-10). Before, each curve was its own byte LUT pass
// and the Float32 buffer was rounded to whole levels between them.

const _sCurve = [
  CurvePoint(0, 0),
  CurvePoint(0.25, 0.18),
  CurvePoint(0.75, 0.82),
  CurvePoint(1, 1),
];
const _lift = [CurvePoint(0, 0.05), CurvePoint(1, 1)];

Float32List _ramp({double step = 1.0}) {
  final n = (255 / step).floor() + 1;
  final img = Float32List(n * 3);
  for (var p = 0; p < n; p++) {
    final v = p * step;
    img[p * 3] = v;
    img[p * 3 + 1] = v;
    img[p * 3 + 2] = v;
  }
  return img;
}

void main() {
  test('every curve identity means no LUTs and an untouched buffer', () {
    expect(
      buildCurveStackLuts(
        parametric: identityParametricCurve,
        curves: identityPhotoCurves,
      ),
      isNull,
    );
    final img = _ramp(step: 0.5);
    final before = Float32List.fromList(img);
    applyCurveStack(
      img,
      parametric: identityParametricCurve,
      curves: identityPhotoCurves,
    );
    expect(img, before);
  });

  test('the stack matches the curves applied one after another, to within '
      'the rounding the old passes introduced', () {
    const curves = PhotoCurves(tone: _sCurve, red: _lift);
    const parametric = ParametricCurve(shadows: 30, highlights: -20);

    final stacked = _ramp();
    applyCurveStack(stacked, parametric: parametric, curves: curves);

    final sequential = _ramp();
    applyToneCurve(sequential, parametricCurvePoints(parametric));
    applyToneCurve(sequential, curves.tone);
    applyColorCurves(sequential, curves.red, curves.green, curves.blue);

    for (var i = 0; i < stacked.length; i++) {
      expect(
        stacked[i],
        closeTo(sequential[i], 1.5),
        reason: 'index $i: stack ${stacked[i]} vs sequential ${sequential[i]}',
      );
    }
  });

  test('fractional input keeps fractional output instead of snapping to '
      'whole levels', () {
    const curves = PhotoCurves(tone: _sCurve);
    final img = Float32List.fromList([100.0, 100.25, 100.5, 100.75, 101.0, 0]);
    applyCurveStack(img, parametric: identityParametricCurve, curves: curves);
    // Strictly increasing across the quarter-levels: the interpolation is
    // real, not a lookup of round(v).
    for (var i = 0; i < 4; i++) {
      expect(img[i + 1], greaterThan(img[i]), reason: 'index $i');
    }
    expect(img[2] - img[0], closeTo((img[4] - img[0]) / 2, 0.01));
  });

  test('a steep curve on a fine ramp does not band: the output keeps as '
      'many distinct values as the input', () {
    const curves = PhotoCurves(tone: _sCurve);
    final img = _ramp(step: 0.25);
    final inputs = <double>{for (var i = 0; i < img.length; i += 3) img[i]};
    applyCurveStack(img, parametric: identityParametricCurve, curves: curves);
    final outputs = <double>{for (var i = 0; i < img.length; i += 3) img[i]};
    // The old byte LUT collapsed 1021 distinct inputs to at most 256
    // outputs; the S-curve is monotone, so the float path keeps them all.
    expect(outputs.length, inputs.length);
  });

  test('the GPU texture and the CPU pass are the same numbers', () {
    const curves = PhotoCurves(tone: _sCurve, green: _lift);
    const parametric = ParametricCurve(darks: 25);
    final luts = buildCurveStackLuts(parametric: parametric, curves: curves)!;
    expect(luts, hasLength(3));
    // Whole-level inputs read the LUT entries exactly.
    final img = Float32List.fromList([0, 0, 0, 128, 128, 128, 255, 255, 255]);
    applyCurveStack(img, parametric: parametric, curves: curves);
    expect(img[0], luts[0][0]);
    expect(img[1], luts[1][0]);
    expect(img[3], luts[0][128]);
    expect(img[4], luts[1][128]);
    expect(img[8], luts[2][255]);
    // Green carries its own curve on top of the shared ones; red and blue
    // share the tone-only result.
    expect(luts[0], luts[2]);
    expect(luts[1][128], greaterThan(luts[0][128]));
  });

  test('out-of-range input is clamped to the curve domain', () {
    const curves = PhotoCurves(tone: _lift);
    final img = Float32List.fromList([-10.0, 300.0, 255.0]);
    applyCurveStack(img, parametric: identityParametricCurve, curves: curves);
    expect(img[0], closeTo(0.05 * 255, 0.01));
    expect(img[1], 255.0);
    expect(img[2], 255.0);
  });
}
