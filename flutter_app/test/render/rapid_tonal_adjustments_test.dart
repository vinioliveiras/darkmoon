import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

Uint8List _solid(int value) => Uint8List.fromList([
      value,
      value,
      value,
      value,
      value,
      value,
      value,
      value,
      value,
      value,
      value,
      value,
    ]);

void main() {
  test('neutral tonal settings preserve the source', () {
    final source = Uint8List.fromList([
      12, 34, 56,
      96, 128, 160,
      200, 180, 150,
      240, 220, 200,
    ]);

    expect(renderRgb(2, 2, source, const RenderParams()), source);
  });

  test('brightness and exposure move the luminance in the expected direction', () {
    final source = _solid(96);
    final brighter = renderRgb(
      2,
      2,
      source,
      const RenderParams(brightness: 50),
    );
    final exposed = renderRgb(
      2,
      2,
      source,
      const RenderParams(exposure: 50),
    );

    expect(brighter[0], greaterThan(source[0]));
    expect(exposed[0], greaterThan(source[0]));
  });

  test('shadows and whites target their respective tonal ranges', () {
    final dark = renderRgb(
      2,
      2,
      _solid(32),
      const RenderParams(shadows: 100),
    );
    final bright = renderRgb(
      2,
      2,
      _solid(224),
      const RenderParams(whites: -100),
    );

    expect(dark[0], greaterThan(32));
    expect(bright[0], lessThan(224));
  });

  test('contrast expands dark and bright tones around the midpoint', () {
    final dark = renderRgb(
      2,
      2,
      _solid(32),
      const RenderParams(contrast: 100),
    );
    final bright = renderRgb(
      2,
      2,
      _solid(224),
      const RenderParams(contrast: 100),
    );

    expect(dark[0], lessThan(32));
    expect(bright[0], greaterThan(224));
  });
}