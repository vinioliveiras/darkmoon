import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:darkmoon/editor_screen.dart';
import 'package:darkmoon/render/render.dart';
import 'package:darkmoon/render/render_params.dart';

/// Default means the photo arrives as decoded.
///
/// It did not. calBaseContrast — a stand-in for the contrast a camera
/// profile bakes in — was applied under every mode including the one that
/// says "no profile". Most visible in embedded-JPEG mode, where the camera
/// had already made those decisions and there was nothing left to stand in
/// for: the image came out with contrast nobody asked for (2026-09-09).
///
/// It read as a *saturation* problem first, which is what makes it worth
/// recording. An S-curve steepens each channel independently, so it pushes
/// them apart: measured on two X-T5 embedded JPEGs, mean saturation went
/// 0.373 -> 0.539 and 0.289 -> 0.399, a 38-45% rise. The filmstrip
/// thumbnail never goes through the render, so it kept the camera's
/// saturation and the two visibly disagreed. At baseContrast 0 the render
/// lands on 0.373 and 0.289 — the source values.
void main() {
  test('Default carries no baseline contrast of its own', () {
    expect(ColorProfileMode.darkmoonDefault.contrastBaseline, 0);
  });

  test('the other modes still do', () {
    // The S-curve is not gone, only scoped: a mode that does apply a
    // profile still wants the contrast that goes with it.
    expect(
      ColorProfileMode.vivid.contrastBaseline,
      greaterThan(0),
      reason: 'scoping Default must not flatten every other mode too',
    );
  });

  test('a render with neither profile nor baseline is a pass-through', () {
    // What "untouched" has to mean at the pixel level. Every stage in the
    // pipeline is a no-op at its default, so the only thing that could
    // move these bytes is a baseline being applied behind the user's back.
    final source = Uint8List.fromList([
      12, 200, 45, //
      255, 0, 128, //
      64, 64, 64, //
      3, 7, 11, //
    ]);
    expect(
      renderRgb(2, 2, source, const RenderParams(baseContrast: 0)),
      source,
    );
  });
}
