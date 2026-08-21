import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../blur.dart' show boxRadiiForGauss;

/// Generic single-shader-pass runner shared by every multi-pass GPU
/// effect from Phase 2 onward (`box_blur_h/v.frag`, `min_filter_h/v.frag`,
/// `downsample_box.frag`, `upsample.frag`, and whatever later phases add)
/// — the GPU-backed analog of `blur.dart`'s CPU helpers. Phase 1's
/// `render_gpu.dart` predates this file and inlines its own version of
/// the same mechanics; not refactored to share this, to avoid touching
/// already-verified code for no functional gain.
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment
/// (Phase 0 confirmed `dart:ui`'s GPU primitives hang inside
/// `Isolate.run`).
class GpuPass {
  GpuPass._();

  static final Map<String, ui.FragmentProgram> _programCache = {};

  static Future<ui.FragmentProgram> loadProgram(String assetPath) async {
    final cached = _programCache[assetPath];
    if (cached != null) {
      return cached;
    }
    final program = await ui.FragmentProgram.fromAsset(assetPath);
    _programCache[assetPath] = program;
    return program;
  }

  /// Runs one shader pass: loads (or reuses the cached) program at
  /// [assetPath], sets [floats] as sequential float uniforms (must match
  /// the shader's own declaration order exactly) and [samplers] as
  /// sequential image-sampler uniforms, then rasterizes into an image of
  /// [outputWidth]x[outputHeight] — which need not match any input
  /// sampler's own size (see `downsample_box.frag`/`upsample.frag`).
  static Future<ui.Image> run(
    String assetPath, {
    required List<double> floats,
    required List<ui.Image> samplers,
    required int outputWidth,
    required int outputHeight,
  }) async {
    final program = await loadProgram(assetPath);
    final shader = program.fragmentShader();
    for (var i = 0; i < floats.length; i++) {
      shader.setFloat(i, floats[i]);
    }
    for (var i = 0; i < samplers.length; i++) {
      shader.setImageSampler(i, samplers[i]);
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
      ui.Paint()..shader = shader,
    );
    final picture = recorder.endRecording();
    return picture.toImage(outputWidth, outputHeight);
  }
}

/// Separable box blur (H then V pass) at [radius] — the GPU counterpart to
/// `blur.dart`'s `boxBlurMean`, shared by every effect (Phase 3's denoise,
/// Phase 4's Sharpen/Texture/Clarity, ...) that needs a plain box blur
/// pass rather than the full Gaussian approximation below.
Future<ui.Image> runBoxBlurGpu(
  ui.Image source,
  int width,
  int height,
  int radius,
) async {
  if (radius <= 0) {
    return source;
  }
  final h = await GpuPass.run(
    'shaders/box_blur_h.frag',
    floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
    samplers: [source],
    outputWidth: width,
    outputHeight: height,
  );
  return GpuPass.run(
    'shaders/box_blur_v.frag',
    floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
    samplers: [h],
    outputWidth: width,
    outputHeight: height,
  );
}

/// Separable min filter (H then V pass) over a `size x size` window — the
/// GPU counterpart to `blur.dart`'s `minFilter`, matching its own
/// `size`-not-`radius` parameter convention (`radius = (size-1) ~/ 2`).
/// Shared by Phase 5's Dehaze (dark-channel spatial min).
Future<ui.Image> runMinFilterGpu(
  ui.Image source,
  int width,
  int height,
  int size,
) async {
  final radius = (size - 1) ~/ 2;
  if (radius <= 0) {
    return source;
  }
  final h = await GpuPass.run(
    'shaders/min_filter_h.frag',
    floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
    samplers: [source],
    outputWidth: width,
    outputHeight: height,
  );
  return GpuPass.run(
    'shaders/min_filter_v.frag',
    floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
    samplers: [h],
    outputWidth: width,
    outputHeight: height,
  );
}

/// GPU port of `blur.dart`'s `gaussianBlurChannel` — 3-pass box-blur
/// approximation, radii from the same [boxRadiiForGauss] the CPU path
/// uses (computed once on CPU, passed as uniforms; not reimplemented in
/// GLSL). Moved here (out of Phase 3's `denoise_gpu.dart`, which
/// originally had this as a private helper) once Phase 4 needed the same
/// Gaussian blur for Sharpen/Texture/Clarity too.
Future<ui.Image> runGaussianBlurGpu(
  ui.Image source,
  int width,
  int height,
  double sigma,
) async {
  var current = source;
  for (final radius in boxRadiiForGauss(sigma, 3)) {
    current = await runBoxBlurGpu(current, width, height, radius);
  }
  return current;
}

/// Packed RGB (3 bytes/pixel) -> RGBA `ui.Image` — shared by
/// `render_gpu.dart` and every Phase 2+ effect that needs to upload a CPU
/// buffer as a source texture (`dart:ui` has no 3-channel pixel format to
/// decode directly).
Future<ui.Image> decodeRgbImage(Uint8List rgb, int width, int height) async {
  final rgba = Uint8List(width * height * 4);
  var src = 0;
  for (var dst = 0; dst < rgba.length; dst += 4, src += 3) {
    rgba[dst] = rgb[src];
    rgba[dst + 1] = rgb[src + 1];
    rgba[dst + 2] = rgb[src + 2];
    rgba[dst + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, (
    image,
  ) {
    completer.complete(image);
  });
  return completer.future;
}

/// The inverse of [decodeRgbImage] — strips alpha from a GPU readback so
/// the result matches the CPU pipeline's packed-RGB `Uint8List` shape.
Uint8List rgbaToRgb(Uint8List rgba) {
  final pixelCount = rgba.length ~/ 4;
  final rgb = Uint8List(pixelCount * 3);
  var src = 0;
  for (var dst = 0; dst < rgb.length; dst += 3, src += 4) {
    rgb[dst] = rgba[src];
    rgb[dst + 1] = rgba[src + 1];
    rgb[dst + 2] = rgba[src + 2];
  }
  return rgb;
}
