import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../mask.dart';
import '../render_params.dart';
import 'gpu_pass.dart';
import 'render_gpu.dart';

/// GPU counterpart to `render.dart`'s `renderRgbWithMasks` — see
/// `project_gpu_render_plan.md`'s Phase 7. Renders the global layer, then
/// each enabled mask layer's own independent re-render of the *current*
/// buffer (matching `renderRgbWithMasks`'s stacking behavior: masks build
/// on top of each other and the global layer, never starting over from the
/// untouched source), alpha-blended in via `shaders/mask_blend.frag`.
///
/// **Mask geometry/alpha computation deliberately stays on CPU**
/// (`mask.dart`'s `computeMaskAlpha`) rather than being ported to GLSL —
/// per the plan's own Phase 7 recommendation: it's cheap (a per-pixel, no-
/// neighbor computation, not a spatial/blur-based one like the effects
/// this port exists to accelerate) and `mask.dart`'s gradient/radial/
/// color-range/brush geometry is a meaningful amount of untouched Dart
/// math not worth porting for little gain. Only the resulting alpha buffer
/// (uploaded as a texture) and the blend itself run on GPU.
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.
Future<Uint8List> renderRgbWithMasksGpu(
  int width,
  int height,
  Uint8List sourceRgb,
  RenderParams globalParams,
  List<MaskLayer> masks,
) async {
  final source = await decodeRgbImage(sourceRgb, width, height);
  var current = await renderImageGpu(source, width, height, globalParams);

  for (final mask in masks) {
    // Same no-op skip as renderRgbWithMasks — a disabled mask, or one with
    // no adjustment values and an identity curve, has nothing to paint.
    if (!mask.enabled || (mask.values.isEmpty && mask.curves.isIdentity)) {
      continue;
    }

    // Only a Color Range mask's alpha depends on pixel color at all —
    // every other mask type ignores sourceForColorRange entirely, so the
    // one CPU readback this loop needs is skipped unless it's actually
    // used.
    Float32List? sourceForColorRange;
    if (mask.type == MaskType.colorRange) {
      final byteData = await current.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final rgb = rgbaToRgb(byteData!.buffer.asUint8List());
      sourceForColorRange = Float32List(rgb.length);
      for (var i = 0; i < rgb.length; i++) {
        sourceForColorRange[i] = rgb[i].toDouble();
      }
    }
    final alpha = computeMaskAlpha(
      mask,
      width,
      height,
      sourceForColorRange: sourceForColorRange,
    );
    final alphaImage = await _alphaToImage(alpha, width, height);

    final layerParams = RenderParams.fromValues(
      mask.values,
      curves: mask.curves,
      asShotKelvin: globalParams.asShotKelvin,
      asShotTint: globalParams.asShotTint,
    );
    final layerImage = await renderImageGpu(
      current,
      width,
      height,
      layerParams,
    );

    current = await GpuPass.run(
      'shaders/mask_blend.frag',
      floats: [width.toDouble(), height.toDouble()],
      samplers: [current, layerImage, alphaImage],
      outputWidth: width,
      outputHeight: height,
    );
  }

  final byteData = await current.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    throw StateError('renderRgbWithMasksGpu: toByteData returned null');
  }
  return rgbaToRgb(byteData.buffer.asUint8List());
}

/// Uploads a single-channel 0..1 alpha buffer as an RGBA `ui.Image` (value
/// replicated across R/G/B, matching every other single-channel texture in
/// this pipeline — e.g. `luminance_extract.frag`'s output).
Future<ui.Image> _alphaToImage(Float32List alpha, int width, int height) async {
  final rgba = Uint8List(width * height * 4);
  for (var p = 0; p < alpha.length; p++) {
    final v = (alpha[p] * 255.0).round().clamp(0, 255);
    final i = p * 4;
    rgba[i] = v;
    rgba[i + 1] = v;
    rgba[i + 2] = v;
    rgba[i + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, (
    image,
  ) {
    completer.complete(image);
  });
  return completer.future;
}
