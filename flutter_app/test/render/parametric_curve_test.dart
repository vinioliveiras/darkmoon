import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';
import 'package:darkmoon/render/tone_curve.dart';

Uint8List _solid(int v) =>
    Uint8List.fromList(List<int>.filled(3, v) + List<int>.filled(3, v));

double _luma(List<int> rgb) =>
    0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];

void main() {
  test('default parametric curve is identity', () {
    expect(const ParametricCurve().isIdentity, isTrue);
    expect(parametricCurvePoints(const ParametricCurve()), identityToneCurve);
  });

  test('ParametricCurve.fromValues reads the flat keys', () {
    final p = ParametricCurve.fromValues({
      'ParamCurveShadows': 40,
      'ParamCurveHighlights': -30,
      'ParamCurveShadowSplit': 20,
    });
    expect(p.shadows, 40);
    expect(p.highlights, -30);
    expect(p.shadowSplit, 20);
    expect(p.midtoneSplit, 50); // default
    expect(p.isIdentity, isFalse);
  });

  test('positive Shadows lifts the dark tones', () {
    final base = renderRgb(1, 2, _solid(40), const RenderParams());
    final lifted = renderRgb(
      1,
      2,
      _solid(40),
      RenderParams(
        parametricCurve: ParametricCurve.fromValues(const {
          'ParamCurveShadows': 80,
        }),
      ),
    );
    expect(_luma(lifted.sublist(0, 3)), greaterThan(_luma(base.sublist(0, 3))));
  });

  test('negative Highlights pulls the bright tones down', () {
    final base = renderRgb(1, 2, _solid(220), const RenderParams());
    final pulled = renderRgb(
      1,
      2,
      _solid(220),
      RenderParams(
        parametricCurve: ParametricCurve.fromValues(const {
          'ParamCurveHighlights': -80,
        }),
      ),
    );
    expect(_luma(pulled.sublist(0, 3)), lessThan(_luma(base.sublist(0, 3))));
  });

  test('endpoints stay pinned at black and white', () {
    final pts = parametricCurvePoints(
      ParametricCurve.fromValues(const {
        'ParamCurveShadows': 100,
        'ParamCurveHighlights': -100,
      }),
    );
    expect(pts.first.x, 0);
    expect(pts.first.y, 0);
    expect(pts.last.x, 1);
    expect(pts.last.y, 1);
  });
}
