import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../calibration.dart';
import '../color_grading.dart';
import '../render_params.dart';
import '../tone_curve.dart';
import '../white_balance.dart';
import 'color_profile_gpu.dart';
import 'dehaze_gpu.dart';
import 'denoise_gpu.dart';
import 'gpu_pass.dart';
import 'local_contrast_gpu.dart';
import 'sharpen_gpu.dart';

/// GPU (fragment-shader) counterpart to `render.dart`'s
/// `_applyAdjustmentSteps` — the full 18-stage pipeline, assembled in
/// Phases 1-6 of `project_gpu_render_plan.md`. Reproduces
/// `applyExposureAndWhiteBalance` followed by `applyLocalAdjustmentSteps`
/// (chroma smoothing through Clarity) followed by `applyGlobalAdjustmentSteps`
/// (Dehaze, Saturation, Vibrance, Vignette, Grain) in the exact same order,
/// each stage delegating to its own phase's module
/// (`denoise_gpu.dart`, `sharpen_gpu.dart`, `local_contrast_gpu.dart`,
/// `dehaze_gpu.dart`) rather than being reimplemented here.
///
/// **Must run on the main isolate** — confirmed in Phase 0
/// (`integration_test/gpu_spike_test.dart`) that `dart:ui`'s GPU-backed
/// primitives hang (not throw) inside `Isolate.run`/`compute()`. Do not
/// call this from a background isolate.
Future<Uint8List> renderRgbaGpu(
  int width,
  int height,
  Uint8List sourceRgb,
  RenderParams params,
) async {
  final source = await decodeRgbImage(sourceRgb, width, height);
  final result = await renderImageGpu(source, width, height, params);
  final byteData = await result.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    throw StateError('renderRgbaGpu: toByteData returned null');
  }
  return byteData.buffer.asUint8List();
}

/// [renderRgbaGpu] narrowed to the CPU pipeline's own packed-RGB shape, so
/// `integration_test/gpu_*` can compare a GPU render against `renderRgb`'s
/// output byte for byte.
///
/// Not what the app itself renders through: `render_job_gpu.dart` wants
/// the RGBA readback as-is (that is the format the canvas uploads from —
/// see `render_job.dart`'s `RenderResult.previewRgba`), and narrowing it
/// here only to widen it right back again was a pair of pointless
/// full-buffer passes on the main isolate.
Future<Uint8List> renderRgbGpu(
  int width,
  int height,
  Uint8List sourceRgb,
  RenderParams params,
) async => rgbaToRgb(await renderRgbaGpu(width, height, sourceRgb, params));

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
  // Exposure -> White Balance -> baseline chroma smoothing -> AI denoise ->
  // Sharpen -> Texture -> Clarity -> Dehaze -> Tone. Exposure/White Balance
  // run first (Solstice's own order runs them much later, after Clarity)
  // so every later stage sees the pixel values the user's actual
  // Temp/Tint/Exposure settings establish, not the camera's raw as-shot
  // decode — see applyExposureAndWhiteBalance's doc comment in
  // render.dart. This matters most for two stages: Dehaze, which
  // estimates its own per-channel "haze color" from whatever buffer it's
  // given (badly wrong on a still-warm as-shot decode, compounding into a
  // magenta cast Meridian never produces); and Clarity's "protect
  // midtones" weight, which reads each pixel's current luminance and
  // targets the wrong tonal range on a RAW that still needs a large
  // Exposure correction.
  final afterExposureAndWb = await _runPreDenoise(
    source,
    width,
    height,
    params,
  );
  final afterChromaSmoothing = await runBaselineChromaSmoothingGpu(
    afterExposureAndWb,
    width,
    height,
  );
  final afterAiDenoise = await runAiDenoiseGpu(
    afterChromaSmoothing,
    width,
    height,
    params.aiDenoise,
  );
  final tonalBlur =
      (params.shadows == 0 && params.blacks == 0 && params.whites == 0)
      ? null
      : await runGaussianBlurGpu(
          await GpuPass.run(
            'shaders/srgb_to_linear.frag',
            floats: [width.toDouble(), height.toDouble()],
            samplers: [afterAiDenoise],
            outputWidth: width,
            outputHeight: height,
          ),
          width,
          height,
          3.5,
        );
  final lut = await _buildLutImage(params.curves, params.parametricCurve);
  final afterSharpen = await runSharpenGpu(
    afterAiDenoise,
    width,
    height,
    params.sharpen,
  );
  final afterTexture = await runLocalContrastGpu(
    afterSharpen,
    width,
    height,
    params.texture * calTextureStrength,
    calTextureSigma,
    noiseAware: true,
  );
  final afterClarity = await runLocalContrastGpu(
    afterTexture,
    width,
    height,
    params.clarity * calClarityStrength,
    calClaritySigma,
    protectMidtones: true,
  );

  // "darkmoon Color" profile stage — the fixed base-contrast S-curve
  // then the per-hue correction, same spot render.dart's
  // applyColorProfileStage runs both in, before Dehaze (see that
  // function's doc comment for why: Dehaze estimates its own haze color
  // from whatever buffer it's given, so any contrast/hue shift needs to
  // happen first). baseContrastGamma moved here 2026-09-02 — it used to
  // be computed and applied inside _runPostDenoise, i.e. *after* Dehaze,
  // a real GPU/CPU order divergence at odds with the comment above.
  final baseContrastGamma = params.baseContrast == 0
      ? 1.0
      : math
            .pow(2.0, params.baseContrast / 100.0 * calContrastStrength)
            .toDouble();
  final afterColorProfile = await runColorProfileGpu(
    afterClarity,
    width,
    height,
    params.colorProfile,
    params.colorProfileStrength,
    baseContrastGamma,
  );
  final afterDehaze = await runDehazeGpu(
    afterColorProfile,
    width,
    height,
    params.dehaze,
  );
  final afterTone = await _runPostDenoise(
    afterDehaze,
    lut,
    tonalBlur,
    width,
    height,
    params,
  );
  return _runPostDehaze(afterTone, width, height, params);
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

  // Same Von Kries per-channel gain as render.dart's _applyWhiteBalance,
  // computed on the Dart side and handed to the shader as flat multipliers
  // (the shader is unchanged).
  final wb = whiteBalanceGains(
    params.temperature,
    params.tint,
    params.asShotKelvin,
    params.asShotTint,
  );
  final normalizedRGain = wb.r;
  final gGain = wb.g;
  final normalizedBGain = wb.b;
  final exposureFactor = math
      .pow(2.0, params.exposure / calExposureUnitsPerStop)
      .toDouble();

  var i = 0;
  shader.setFloat(i++, width.toDouble());
  shader.setFloat(i++, height.toDouble());
  shader.setFloat(i++, normalizedRGain);
  shader.setFloat(i++, normalizedBGain);
  shader.setFloat(i++, gGain);
  shader.setFloat(i++, 1.0);
  shader.setFloat(i++, exposureFactor);
  shader.setImageSampler(0, source);

  return _rasterize(shader, width, height);
}

Future<ui.Image> _runPostDenoise(
  ui.Image source,
  ui.Image lut,
  ui.Image? tonalBlur,
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

  // Endpoint-preserving S-curve gamma — mirrors render.dart's
  // _applyBrightnessContrast exactly (see its doc comment for why this
  // replaced a plain linear contrastFactor).
  final contrastGamma = params.contrast == 0
      ? 1.0
      : math.pow(2.0, params.contrast / 100.0 * calContrastStrength).toDouble();
  final shadowsAdd = params.shadows / 100.0;
  final highlightsAdd = params.highlights / 100.0;
  final whitesAdd = params.whites / 100.0;
  final blacksAdd = params.blacks / 100.0;

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
  shader.setFloat(i++, params.brightness / calBrightnessUnitsPerStop);
  shader.setFloat(i++, contrastGamma);
  shader.setFloat(i++, shadowsAdd);
  shader.setFloat(i++, highlightsAdd);
  shader.setFloat(i++, whitesAdd);
  shader.setFloat(i++, blacksAdd);
  shader.setFloat(i++, calHighlightsStrength);
  shader.setFloat(i++, calShadowsAmountScale);
  shader.setFloat(i++, calBlacksAmountScale);
  shader.setFloat(i++, calBrightnessMidtoneStrength);
  shader.setFloat(i++, calWhitesMaskLow);
  shader.setFloat(i++, calWhitesLevelCoeff);
  shader.setFloat(i++, calShadowsFalloff);
  shader.setFloat(i++, calBlacksFalloff);
  shader.setFloat(i++, calShadowBlacksStretch);
  shader.setFloat(i++, calShadowBlacksContrastMix);
  shader.setFloat(i++, calMixerHueStrength);
  shader.setFloat(i++, calMixerBandSharpness);
  shader.setFloat(i++, calMixerSaturationStrength);
  shader.setFloat(i++, calMixerLuminanceStrength);
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
  shader.setImageSampler(2, tonalBlur ?? source);

  return _rasterize(shader, width, height);
}

/// Fused Saturation + Vibrance + Vignette + Grain pass — see
/// `shaders/post_dehaze.frag`'s doc comment for why these are their
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
  final vignetteStrength = vignette.amount / 100.0 * calVignetteStrength;
  final vignetteStart = (vignette.midpoint / 100.0).clamp(0.0, 1.0);
  final vignetteFeatherWidth = (vignette.feather / 100.0).clamp(0.02, 1.0);

  // Grain — mirrors grain.dart's applyGrain exactly, minus the CPU path's
  // `* 255.0` (this shader stays in 0..1 space) and any rowOffset/
  // fullHeight banding math (the GPU path always renders the whole image
  // in one dispatch, never a band, so fullHeight == height here).
  final grain = params.grain;
  final grainAmount = grain.isIdentity
      ? 0.0
      : (grain.amount / 100.0) * 0.5 * calGrainStrength;
  final grainSizePx =
      calGrainSizePxAt0 +
      (grain.size / 100.0).clamp(0.0, 1.0) *
          (calGrainSizePxAt100 - calGrainSizePxAt0);
  final grainRefScale = math.max(0.1, math.min(width, height) / 1080.0);
  final grainFrequency = (1.0 / math.max(grainSizePx, 0.1)) / grainRefScale;
  final grainRoughFrequency = grainFrequency * calGrainRoughCoordScale;
  final grainRoughness = (grain.roughness / 100.0).clamp(0.0, 1.0);

  var i = 0;
  shader.setFloat(i++, width.toDouble());
  shader.setFloat(i++, height.toDouble());
  shader.setFloat(i++, params.vibrance / 100.0);
  shader.setFloat(i++, 1.0 + params.saturation / 100.0 * calSaturationStrength);
  shader.setFloat(i++, calVibranceStrength);
  shader.setFloat(i++, calVibranceSkinDampen);
  shader.setFloat(i++, vignetteStrength);
  shader.setFloat(i++, vignetteStart);
  shader.setFloat(i++, vignetteFeatherWidth);
  shader.setFloat(i++, grainAmount);
  shader.setFloat(i++, grainFrequency);
  shader.setFloat(i++, grainRoughFrequency);
  shader.setFloat(i++, grainRoughness);
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

/// Identity mapping (lut[i] == i) — used in place of [buildToneCurveLut]'s
/// own output for the default 2-point curve, purely as a cheap shortcut
/// (skips the per-entry Hermite evaluation for the overwhelmingly common
/// no-curve case). `tone_curve.dart`'s own `applyToneCurve`/
/// `applyColorCurves` take the equivalent shortcut via `isIdentityToneCurve`
/// before ever calling `buildToneCurveLut`, but the GPU path has no such
/// early-return (the shader always samples the LUT texture), so it
/// substitutes this identity LUT directly instead.
///
/// Historical note: back when [buildToneCurveLut] used a plain Catmull-Rom
/// spline, this substitution wasn't just a shortcut but a correctness fix —
/// that spline didn't reduce to a true straight line even for
/// `identityToneCurve`'s two collinear points (it evaluated to a visible
/// S-curve, e.g. ~0.203 at t=0.25 instead of 0.25), which is what
/// integration_test/gpu_point_ops_test.dart's "neutral params" case (a
/// ~15/255 mean diff unrelated to the params under test) first caught.
/// [buildToneCurveLut] now uses the same monotone cubic Hermite spline as
/// Solstice's `apply_curve`, which doesn't have that flaw for *any* input
/// (collinear or not) — this substitution stays only for performance.
final Uint8List _identityLut = Uint8List.fromList(
  List<int>.generate(256, (i) => i),
);

Uint8List _lutFor(List<CurvePoint> points) =>
    isIdentityToneCurve(points) ? _identityLut : buildToneCurveLut(points);

/// Builds the 256x1 RGBA LUT texture consumed by
/// `point_ops_post_denoise.frag`'s `uLut` — r = tone curve, g/b/a =
/// red/green/blue color curves, each from [_lutFor] (which defers to
/// `tone_curve.dart`'s own `buildToneCurveLut` for a real curve).
Future<ui.Image> _buildLutImage(
  PhotoCurves curves,
  ParametricCurve parametric,
) async {
  var tone = _lutFor(curves.tone);
  if (!parametric.isIdentity) {
    // Compose parametric-then-point into the single `uLut.r` channel the
    // shader reads, so no shader change is needed: combined[i] =
    // pointCurve(parametricCurve(i)).
    final paramLut = buildToneCurveLut(parametricCurvePoints(parametric));
    final composed = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      composed[i] = tone[paramLut[i]];
    }
    tone = composed;
  }
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
