import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_grading.dart';
import '../render_params.dart';
import '../tone_curve.dart';
import 'dehaze_gpu.dart';
import 'denoise_gpu.dart';
import 'local_contrast_gpu.dart';
import 'sharpen_gpu.dart';

/// GPU (fragment-shader) counterpart to `render.dart`'s
/// `_applyAdjustmentSteps` — the full 18-stage pipeline, assembled in
/// Phases 1-6 of `project_gpu_render_plan.md`. Reproduces
/// `applyLocalAdjustmentSteps` (white balance through Clarity) followed by
/// `applyGlobalAdjustmentSteps` (Dehaze, Vibrance, Saturation, Vignette) in
/// the exact same order, each stage delegating to its own phase's module
/// (`denoise_gpu.dart`, `sharpen_gpu.dart`, `local_contrast_gpu.dart`,
/// `dehaze_gpu.dart`) rather than being reimplemented here.
///
/// **Must run on the main isolate** — confirmed in Phase 0
/// (`integration_test/gpu_spike_test.dart`) that `dart:ui`'s GPU-backed
/// primitives hang (not throw) inside `Isolate.run`/`compute()`. Do not
/// call this from a background isolate.
Future<Uint8List> renderRgbGpu(
  int width,
  int height,
  Uint8List sourceRgb,
  RenderParams params,
) async {
  final source = await _decodeRgbImage(sourceRgb, width, height);
  final result = await renderImageGpu(source, width, height, params);
  final byteData = await result.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    throw StateError('renderRgbGpu: toByteData returned null');
  }
  return _rgbaToRgb(byteData.buffer.asUint8List());
}

/// The `ui.Image`-in/`ui.Image`-out core of [renderRgbGpu], split out so
/// `mask_gpu.dart`'s `renderRgbWithMasksGpu` (Phase 7) can chain the global
/// layer and each mask layer's own independent render straight from one
/// `ui.Image` to the next, without a wasted Uint8List readback/re-upload
/// round trip between them.
Future<ui.Image> renderImageGpu(
  ui.Image source,
  int width,
  int height,
  RenderParams params,
) async {
  // applyLocalAdjustmentSteps' order: pre-denoise point ops -> baseline
  // chroma smoothing (always on) -> AI denoise -> post-denoise point ops
  // -> Sharpen -> Texture -> Clarity.
  final afterPreDenoise = await _runPreDenoise(source, width, height, params);
  final afterChromaSmoothing = await runBaselineChromaSmoothingGpu(
    afterPreDenoise,
    width,
    height,
  );
  final afterAiDenoise = await runAiDenoiseGpu(
    afterChromaSmoothing,
    width,
    height,
    params.aiDenoise,
  );
  final lut = await _buildLutImage(params.curves);
  final afterPostDenoise = await _runPostDenoise(
    afterAiDenoise,
    lut,
    width,
    height,
    params,
  );
  final afterSharpen = await runSharpenGpu(
    afterPostDenoise,
    width,
    height,
    params.sharpen,
  );
  final afterTexture = await runLocalContrastGpu(
    afterSharpen,
    width,
    height,
    params.texture,
    3,
    noiseAware: true,
  );
  final afterClarity = await runLocalContrastGpu(
    afterTexture,
    width,
    height,
    params.clarity,
    25,
    protectMidtones: true,
  );

  // applyGlobalAdjustmentSteps' order: Dehaze -> Vibrance -> Saturation ->
  // Vignette, on the complete buffer (never per-band — see that function's
  // doc comment; GPU has no band concept at all, so this is automatic here).
  final afterDehaze = await runDehazeGpu(
    afterClarity,
    width,
    height,
    params.dehaze,
  );
  return _runPostDehaze(afterDehaze, width, height, params);
}

ui.FragmentProgram? _preDenoiseProgram;
ui.FragmentProgram? _postDenoiseProgram;
ui.FragmentProgram? _postDehazeProgram;

Future<ui.FragmentProgram> _loadProgram(
  String assetPath,
  ui.FragmentProgram? Function() getCached,
  void Function(ui.FragmentProgram) setCached,
) async {
  final cached = getCached();
  if (cached != null) {
    return cached;
  }
  final program = await ui.FragmentProgram.fromAsset(assetPath);
  setCached(program);
  return program;
}

Future<ui.Image> _runPreDenoise(
  ui.Image source,
  int width,
  int height,
  RenderParams params,
) async {
  final program = await _loadProgram(
    'shaders/point_ops_pre_denoise.frag',
    () => _preDenoiseProgram,
    (p) => _preDenoiseProgram = p,
  );
  final shader = program.fragmentShader();

  const neutralKelvin = 5500.0;
  const miredGainPerUnit = 0.0013;
  final miredDelta = 1.0e6 / neutralKelvin - 1.0e6 / params.temperature;
  final tempGain = (miredDelta * miredGainPerUnit).clamp(-0.6, 0.6);
  final rGain = 1.0 + tempGain;
  final bGain = 1.0 - tempGain;
  final tintShift = params.tint / 100.0 * 0.2;
  final gGain = 1.0 - tintShift;
  final rbGain = 1.0 + tintShift * 0.5;
  final exposureFactor = math
      .pow(2.0, params.exposure / 100.0 * 3.0)
      .toDouble();

  var i = 0;
  shader.setFloat(i++, width.toDouble());
  shader.setFloat(i++, height.toDouble());
  shader.setFloat(i++, rGain);
  shader.setFloat(i++, bGain);
  shader.setFloat(i++, gGain);
  shader.setFloat(i++, rbGain);
  shader.setFloat(i++, exposureFactor);
  shader.setImageSampler(0, source);

  return _rasterize(shader, width, height);
}

Future<ui.Image> _runPostDenoise(
  ui.Image source,
  ui.Image lut,
  int width,
  int height,
  RenderParams params,
) async {
  final program = await _loadProgram(
    'shaders/point_ops_post_denoise.frag',
    () => _postDenoiseProgram,
    (p) => _postDenoiseProgram = p,
  );
  final shader = program.fragmentShader();

  final contrastFactor = 1.0 + params.contrast / 100.0;
  final shadowsAdd = params.shadows / 100.0 * 80.0 / 255.0;
  final highlightsAdd = params.highlights / 100.0 * 80.0 / 255.0;
  final whitesAdd = params.whites / 100.0 * 100.0 / 255.0;
  final blacksAdd = params.blacks / 100.0 * 100.0 / 255.0;

  final mixerChannels = [
    params.colorMixer.red,
    params.colorMixer.orange,
    params.colorMixer.yellow,
    params.colorMixer.green,
    params.colorMixer.aqua,
    params.colorMixer.blue,
    params.colorMixer.purple,
    params.colorMixer.magenta,
  ];

  final shadowTint = gradeTintOffset(
    params.colorGrading.shadows,
  ).map((v) => v / 255.0).toList();
  final midTint = gradeTintOffset(
    params.colorGrading.midtones,
  ).map((v) => v / 255.0).toList();
  final highlightTint = gradeTintOffset(
    params.colorGrading.highlights,
  ).map((v) => v / 255.0).toList();
  final globalTint = gradeTintOffset(
    params.colorGrading.global,
  ).map((v) => v / 255.0).toList();

  var i = 0;
  shader.setFloat(i++, width.toDouble());
  shader.setFloat(i++, height.toDouble());
  shader.setFloat(i++, params.brightness);
  shader.setFloat(i++, contrastFactor);
  shader.setFloat(i++, shadowsAdd);
  shader.setFloat(i++, highlightsAdd);
  shader.setFloat(i++, whitesAdd);
  shader.setFloat(i++, blacksAdd);
  for (final ch in mixerChannels) {
    shader.setFloat(i++, ch.hue);
    shader.setFloat(i++, ch.saturation);
    shader.setFloat(i++, ch.luminance);
  }
  for (final v in shadowTint) {
    shader.setFloat(i++, v);
  }
  for (final v in midTint) {
    shader.setFloat(i++, v);
  }
  for (final v in highlightTint) {
    shader.setFloat(i++, v);
  }
  for (final v in globalTint) {
    shader.setFloat(i++, v);
  }
  shader.setFloat(
    i++,
    params.colorGrading.shadows.luminance / 100.0 * 80.0 / 255.0,
  );
  shader.setFloat(
    i++,
    params.colorGrading.midtones.luminance / 100.0 * 80.0 / 255.0,
  );
  shader.setFloat(
    i++,
    params.colorGrading.highlights.luminance / 100.0 * 80.0 / 255.0,
  );
  shader.setFloat(
    i++,
    params.colorGrading.global.luminance / 100.0 * 80.0 / 255.0,
  );
  shader.setImageSampler(0, source);
  shader.setImageSampler(1, lut);

  return _rasterize(shader, width, height);
}

/// Fused Vibrance + Saturation + Vignette pass — see
/// `shaders/post_dehaze.frag`'s doc comment for why these three are their
/// own small post-Dehaze pass rather than folded into
/// `_runPostDenoise`'s shader.
Future<ui.Image> _runPostDehaze(
  ui.Image source,
  int width,
  int height,
  RenderParams params,
) async {
  final program = await _loadProgram(
    'shaders/post_dehaze.frag',
    () => _postDehazeProgram,
    (p) => _postDehazeProgram = p,
  );
  final shader = program.fragmentShader();

  final vignette = params.vignette;
  final vignetteStrength = vignette.amount / 100.0 * 0.8;
  final vignetteStart = (vignette.midpoint / 100.0).clamp(0.0, 1.0);
  final vignetteFeatherWidth = (vignette.feather / 100.0).clamp(0.02, 1.0);

  var i = 0;
  shader.setFloat(i++, width.toDouble());
  shader.setFloat(i++, height.toDouble());
  shader.setFloat(i++, params.vibrance / 100.0);
  shader.setFloat(i++, 1.0 + params.saturation / 100.0);
  shader.setFloat(i++, vignetteStrength);
  shader.setFloat(i++, vignetteStart);
  shader.setFloat(i++, vignetteFeatherWidth);
  shader.setImageSampler(0, source);

  return _rasterize(shader, width, height);
}

Future<ui.Image> _rasterize(
  ui.FragmentShader shader,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}

/// Identity mapping (lut[i] == i) — used in place of
/// [buildToneCurveLut]'s own output for the default 2-point curve.
/// `buildToneCurveLut`'s Catmull-Rom interpolation does NOT reduce to a
/// true straight line even for `identityToneCurve`'s two collinear points
/// (verified empirically: it evaluates to a visible S-curve, e.g. ~0.203
/// at t=0.25 instead of 0.25) — `tone_curve.dart`'s own `applyToneCurve`/
/// `applyColorCurves` never actually hit this, because they early-return
/// via `isIdentityToneCurve` before ever calling `buildToneCurveLut` on an
/// identity curve. The GPU path has no such early-return (the shader
/// always samples the LUT texture), so it must substitute a genuinely
/// identity LUT itself here instead of feeding the distorted one to the
/// shader — this was Phase 1's first real bug, caught by
/// integration_test/gpu_point_ops_test.dart's "neutral params" case
/// showing a ~15/255 mean diff that had nothing to do with the params
/// under test.
final Uint8List _identityLut = Uint8List.fromList(
  List<int>.generate(256, (i) => i),
);

Uint8List _lutFor(List<CurvePoint> points) =>
    isIdentityToneCurve(points) ? _identityLut : buildToneCurveLut(points);

/// Builds the 256x1 RGBA LUT texture consumed by
/// `point_ops_post_denoise.frag`'s `uLut` — r = tone curve, g/b/a =
/// red/green/blue color curves, each from [_lutFor] (which defers to
/// `tone_curve.dart`'s own `buildToneCurveLut` for a real curve).
Future<ui.Image> _buildLutImage(PhotoCurves curves) async {
  final tone = _lutFor(curves.tone);
  final red = _lutFor(curves.red);
  final green = _lutFor(curves.green);
  final blue = _lutFor(curves.blue);
  final bytes = Uint8List(256 * 4);
  for (var x = 0; x < 256; x++) {
    bytes[x * 4] = tone[x];
    bytes[x * 4 + 1] = red[x];
    bytes[x * 4 + 2] = green[x];
    bytes[x * 4 + 3] = blue[x];
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(bytes, 256, 1, ui.PixelFormat.rgba8888, (image) {
    completer.complete(image);
  });
  return completer.future;
}

/// Packed RGB (3 bytes/pixel) -> RGBA `ui.Image`, since `dart:ui` has no
/// 3-channel pixel format to decode directly.
Future<ui.Image> _decodeRgbImage(Uint8List rgb, int width, int height) async {
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

/// The inverse of [_decodeRgbImage] — strips alpha from a GPU readback so
/// the result matches `renderRgb`/`renderAdjustmentsParallel`'s packed-RGB
/// `Uint8List` shape, keeping every downstream caller
/// (`render_job.dart`'s histogram/JPEG-encode/thumbnail) unchanged.
Uint8List _rgbaToRgb(Uint8List rgba) {
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
