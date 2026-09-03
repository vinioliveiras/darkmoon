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
/// Gain applied to `shaders/residual_sq.frag`'s output before it is
/// written to an 8-bit render target, and divided back out by every
/// consumer (`denoise_combine.frag`, `local_contrast_combine.frag`,
/// `sharpen_combine.frag`).
///
/// A squared residual for photographic noise is on the order of 1e-4 in
/// this pipeline's 0..1 working space, well under an 8-bit target's
/// 1/255 quantization step — without a gain it rounds to zero and the
/// local noise variance every consumer reads is zero almost everywhere.
/// See residual_sq.frag's own comment for what that broke.
///
/// 512 puts the resolution at ~0.5 of the CPU path's own 0-255 variance
/// units and only saturates above ~127 of them (a residual around 11
/// levels), which is deep into real-edge territory where saturating is
/// the harmless direction — see residual_sq.frag.
const double gpuResidualSqScale = 512.0;

/// Holds the intermediate `ui.Image`s one stage of the GPU pipeline
/// creates, so they can be released as soon as that stage is done with
/// them.
///
/// Every pass rasterizes into a brand-new full-size RGBA image, and a full
/// render runs 50+ passes — at full-quality resolution that is well over a
/// gigabyte of GPU-side texture per render. `ui.Image` releases that only
/// on an explicit `dispose()`: the finalizer exists but runs late and
/// unpredictably, which is what let a long editing session drift into
/// multi-gigabyte memory use.
///
/// Batched per stage rather than "dispose the previous image as you go"
/// because several helpers return their *input* unchanged when they have
/// nothing to do (`runBoxBlurGpu` at radius 0, `runSharpenGpu` on identity
/// params, …), so the previous image is not reliably dead. An identity
/// [Set] backs it, so registering the same image twice — which happens
/// naturally when one of those no-op paths is taken — still disposes it
/// exactly once.
class GpuImagePool {
  final Set<ui.Image> _images = Set<ui.Image>.identity();

  /// Registers [image] as this stage's to release, and returns it.
  ui.Image add(ui.Image image) {
    _images.add(image);
    return image;
  }

  /// Disposes everything registered except [keep] — the image whose
  /// ownership passes to the caller. Leaves the pool empty.
  void disposeAllExcept([ui.Image? keep]) {
    for (final image in _images) {
      if (!identical(image, keep)) {
        image.dispose();
      }
    }
    _images.clear();
  }
}

class GpuPass {
  GpuPass._();

  /// How many shader passes have been rasterized since [resetPassCount].
  ///
  /// Every pass is its own `Picture.toImage()`, i.e. its own render-target
  /// allocation and GPU submit — measured at ~27ms each on a 6 MP frame,
  /// independent of how much math the shader does. That makes the pass
  /// count, not the tap count, the thing worth optimizing, so it is worth
  /// being able to read it. Incremented by [run] and by `render_gpu.dart`'s
  /// own `_rasterize` (the two places that call `toImage`).
  static int passCount = 0;

  /// Passes broken down by shader asset — names the fusion targets.
  static final Map<String, int> passCountByShader = {};

  static void resetPassCount() {
    passCount = 0;
    passCountByShader.clear();
  }

  static void countPass(String assetPath) {
    passCount++;
    passCountByShader.update(assetPath, (v) => v + 1, ifAbsent: () => 1);
  }

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
    countPass(assetPath);
    // Both the picture and the shader hold native resources of their own,
    // released only on an explicit dispose. They are safe to drop as soon
    // as the image exists — the picture has been rasterized, and the
    // shader was only ever referenced by the paint inside it.
    final image = await picture.toImage(outputWidth, outputHeight);
    picture.dispose();
    shader.dispose();
    return image;
  }
}

/// Separable box blur (H then V pass) at [radius] — the GPU counterpart to
/// `blur.dart`'s `boxBlurMean`, shared by every effect (Phase 3's denoise,
/// Phase 4's Sharpen/Texture/Clarity, ...) that needs a plain box blur
/// pass rather than the full Gaussian approximation below.
/// Largest radius [runBoxBlurGpu] will do in a single fused 2D pass
/// (`box_blur_2d.frag`) instead of the separable horizontal/vertical pair.
///
/// A pass costs ~20-25ms on a 6 MP frame no matter what it does — that is
/// render-target allocation and GPU submit, not shader work — while the
/// taps themselves are close to free at these counts (Clarity's 41-tap
/// blur and Texture's 5-tap blur measured identically per pass). So one
/// pass of (2r+1)^2 taps beats two of (2r+1) until the tap count grows
/// enough to matter, which is what this caps.
///
/// Measured, not guessed: raising this to 40 (so Clarity's sigma-35 and
/// Dehaze's sigma-40 blurs fused too, at radius ~34) took Clarity from
/// 527ms to 1265ms and Dehaze from 501ms to 1497ms on the same 6 MP
/// frame. Every radius this pipeline actually uses below Clarity/Dehaze
/// is 7 or less, so anything from ~8 to ~33 behaves identically here; 16
/// sits safely in the middle of that gap.
const int fusedBoxBlurMaxRadius = 16;

Future<ui.Image> runBoxBlurGpu(
  ui.Image source,
  int width,
  int height,
  int radius,
) async {
  if (radius <= 0) {
    return source;
  }
  if (radius <= fusedBoxBlurMaxRadius) {
    return GpuPass.run(
      'shaders/box_blur_2d.frag',
      floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
      samplers: [source],
      outputWidth: width,
      outputHeight: height,
    );
  }
  final h = await GpuPass.run(
    'shaders/box_blur_h.frag',
    floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
    samplers: [source],
    outputWidth: width,
    outputHeight: height,
  );
  final result = await GpuPass.run(
    'shaders/box_blur_v.frag',
    floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
    samplers: [h],
    outputWidth: width,
    outputHeight: height,
  );
  // The horizontal half is dead the moment the vertical one has consumed
  // it; [source] belongs to the caller and is never touched here.
  h.dispose();
  return result;
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
  final result = await GpuPass.run(
    'shaders/min_filter_v.frag',
    floats: [width.toDouble(), height.toDouble(), radius.toDouble()],
    samplers: [h],
    outputWidth: width,
    outputHeight: height,
  );
  h.dispose();
  return result;
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
    final next = await runBoxBlurGpu(current, width, height, radius);
    // Each pass's input dies with it — except [source], which belongs to
    // the caller, and except the no-op case (radius 0) where runBoxBlurGpu
    // hands the very same image straight back.
    if (!identical(current, source) && !identical(current, next)) {
      current.dispose();
    }
    current = next;
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
