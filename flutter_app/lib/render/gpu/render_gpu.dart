import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../blur.dart' show scaledNoiseRadius;
import '../calibration.dart';
import '../color_grading.dart';
import '../film_lut.dart';
import '../render.dart' show needsTonalBlur;
import '../render_params.dart';
import '../tone_curve.dart';
import '../white_balance.dart';
import 'color_profile_gpu.dart';
import 'dehaze_gpu.dart';
import 'denoise_gpu.dart';
import 'gpu_pass.dart';
import 'gpu_stage_cache.dart';
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
  final result = await renderImageGpuFromRgb(width, height, sourceRgb, params);
  final ByteData? byteData;
  try {
    byteData = await result.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    // Everything this render allocated is gone by here: renderImageGpu
    // released its own chain, and this is the one image it handed back.
    result.dispose();
  }
  if (byteData == null) {
    throw StateError('renderRgbaGpu: toByteData returned null');
  }
  return byteData.buffer.asUint8List();
}

/// [renderRgbaGpu] without the readback: the finished frame as the
/// `ui.Image` the chain produced, for a caller that will paint it (the
/// editor's canvas, since 2026-09-11) rather than read its pixels. The
/// caller owns the image.
Future<ui.Image> renderImageGpuFromRgb(
  int width,
  int height,
  Uint8List sourceRgb,
  RenderParams params,
) async {
  // The source upload is itself a full-frame copy plus a texture upload;
  // when the stage cache can resume from a stored boundary it is never
  // sampled, so it is skipped too. See GpuStageCache.
  final fingerprint = GpuStageCache.sourceFingerprint(sourceRgb, width, height);
  final source =
      GpuStageCache.instance.canResume(fingerprint, width, height, params)
      ? null
      : await decodeRgbImage(sourceRgb, width, height);
  try {
    return await renderImageGpu(
      source,
      width,
      height,
      params,
      sourceFingerprint: fingerprint,
    );
  } finally {
    source?.dispose();
  }
}

/// [image] ([width] x [height]) drawn down so its long edge is at most
/// [maxDimension] — bilinear, one draw call — for the small readbacks
/// that feed the histogram and the filmstrip thumbnail. Returns [image]
/// itself when it already fits; otherwise a new image the caller owns.
Future<ui.Image> scaleGpuImage(
  ui.Image image,
  int width,
  int height,
  int maxDimension,
) async {
  final longEdge = math.max(width, height);
  if (longEdge <= maxDimension) {
    return image;
  }
  final scale = maxDimension / longEdge;
  final w = math.max(1, (width * scale).round());
  final h = math.max(1, (height * scale).round());
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    image,
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.low,
  );
  final picture = recorder.endRecording();
  GpuPass.countPass('scale');
  try {
    return await picture.toImage(w, h);
  } finally {
    picture.dispose();
  }
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
///
/// Owns every image it creates and releases them before returning, keeping
/// only the frame it hands back (see [GpuImagePool] for why that matters
/// — this chain alone is a dozen full-size RGBA textures, and the stages
/// it calls allocate several times that between them). [source] belongs to
/// the caller and is never disposed here.
///
/// With a [sourceFingerprint] (see [GpuStageCache.sourceFingerprint]) the
/// chain consults [GpuStageCache] and resumes from the deepest boundary
/// whose parameters match, storing the boundaries it does compute for the
/// next render. [source] may then be `null` when the caller already knows
/// a boundary will hit ([GpuStageCache.canResume]); it is only read when
/// the chain has to start from the top. Without a fingerprint — the mask
/// layers — nothing is cached and [source] is required.
Future<ui.Image> renderImageGpu(
  ui.Image? source,
  int width,
  int height,
  RenderParams params, {
  int? sourceFingerprint,
}) async {
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
  // Cross-render cache (2026-09-09, see GpuStageCache): the two boundaries
  // are looked up first, deepest first, and everything before the hit is
  // skipped. A Basic-panel slider change then runs only the tonal blur
  // and the two point-op passes instead of the whole chain.
  final cache = sourceFingerprint == null ? null : GpuStageCache.instance;
  final keyAfterAiDenoise = cache == null
      ? null
      : GpuStageCache.keyFor(
          GpuStageBoundary.afterAiDenoise,
          sourceFingerprint!,
          width,
          height,
          params,
        );
  final keyAfterDehaze = cache == null
      ? null
      : GpuStageCache.keyFor(
          GpuStageBoundary.afterDehaze,
          sourceFingerprint!,
          width,
          height,
          params,
        );
  final cachedAfterDehaze = cache?.lookup(
    GpuStageBoundary.afterDehaze,
    keyAfterDehaze!,
  );
  final cachedAfterAiDenoise = cachedAfterDehaze != null
      ? null
      : cache?.lookup(GpuStageBoundary.afterAiDenoise, keyAfterAiDenoise!);

  // The source belongs to the caller and the cached images to the cache:
  // none of them is this chain's to dispose.
  final chain = GpuImagePool([
    if (source != null) source,
    if (cachedAfterDehaze != null) cachedAfterDehaze,
    if (cachedAfterAiDenoise != null) cachedAfterAiDenoise,
  ]);

  final ui.Image afterDehaze;
  if (cachedAfterDehaze != null) {
    afterDehaze = cachedAfterDehaze;
  } else {
    final ui.Image afterAiDenoise;
    if (cachedAfterAiDenoise != null) {
      afterAiDenoise = cachedAfterAiDenoise;
    } else {
      if (source == null) {
        throw StateError(
          'renderImageGpu: no source image and no cached stage to resume '
          'from (canResume said otherwise)',
        );
      }
      final afterExposureAndWb = chain.add(
        await _runPreDenoise(source, width, height, params),
      );
      // detailScale, not renderScale, on all three of chroma smoothing,
      // denoise and sharpen — mirrors render.dart's CPU ordering exactly.
      // See calDetailRadiusMaxScale.
      final afterChromaSmoothing = chain.add(
        await runBaselineChromaSmoothingGpu(
          afterExposureAndWb,
          width,
          height,
          params.detailScale,
        ),
      );
      afterAiDenoise = chain.add(
        await runAiDenoiseGpu(
          afterChromaSmoothing,
          width,
          height,
          params.aiDenoise,
          params.detailScale,
        ),
      );
      if (cache != null &&
          cache.adopt(
            GpuStageBoundary.afterAiDenoise,
            keyAfterAiDenoise!,
            afterAiDenoise,
          )) {
        chain.detach(afterAiDenoise);
      }
    }
    final afterSharpen = chain.add(
      await runSharpenGpu(
        afterAiDenoise,
        width,
        height,
        params.sharpen,
        params.detailScale,
      ),
    );
    final afterTexture = chain.add(
      await runLocalContrastGpu(
        afterSharpen,
        width,
        height,
        params.texture * calTextureStrength,
        calTextureSigma * params.renderScale,
        noiseAware: true,
        noiseRadius: scaledNoiseRadius(params.renderScale),
      ),
    );
    final afterClarity = chain.add(
      await runLocalContrastGpu(
        afterTexture,
        width,
        height,
        params.clarity * calClarityStrength,
        calClaritySigma * params.renderScale,
        protectMidtones: true,
        edgeThreshold: calClarityEdgeThreshold,
        tonal: params.clarityTonal,
      ),
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
    final afterColorProfile = chain.add(
      await runColorProfileGpu(
        afterClarity,
        width,
        height,
        params.colorProfile,
        params.colorProfileStrength,
        baseContrastGamma,
      ),
    );
    afterDehaze = chain.add(
      await runDehazeGpu(
        afterColorProfile,
        width,
        height,
        params.dehaze,
        params.renderScale,
      ),
    );
    if (cache != null &&
        cache.adopt(
          GpuStageBoundary.afterDehaze,
          keyAfterDehaze!,
          afterDehaze,
        )) {
      chain.detach(afterDehaze);
    }
  }
  final lut = chain.add(
    await _buildLutImage(params.curves, params.parametricCurve),
  );
  // The sigma-3.5 tonal blur behind Shadows/Blacks' detail preservation,
  // taken from the post-Dehaze buffer because that is where the CPU takes
  // it: render.dart computes it at the top of applyPostDenoisePointOps,
  // which runs after applyColorProfileStage and applyDehazeStage.
  //
  // Real GPU/CPU divergence fixed 2026-09-03: this used to be computed
  // from afterAiDenoise, i.e. before Sharpen, Texture, Clarity, the colour
  // profile and Dehaze. calBaseContrast is 80 and always on, so the
  // profile's S-curve alone put the blurred luminance the shader reads in
  // a completely different tonal range from the CPU's — which then fed
  // rapidShadowsBlacks' detailRatio, noiseProtection and detailExponent.
  // Same class of bug as the base-contrast ordering fixed 2026-09-02.
  final ui.Image? tonalBlur;
  if (!needsTonalBlur(params)) {
    tonalBlur = null;
  } else {
    final linear = chain.add(
      await GpuPass.run(
        'shaders/srgb_to_linear.frag',
        floats: [width.toDouble(), height.toDouble()],
        samplers: [afterDehaze],
        outputWidth: width,
        outputHeight: height,
      ),
    );
    tonalBlur = chain.add(
      await runGaussianBlurGpu(linear, width, height, 3.5 * params.renderScale),
    );
  }

  final afterTone = chain.add(
    await _runPostDenoise(afterDehaze, lut, tonalBlur, width, height, params),
  );
  final film = params.filmLut;
  final ui.Image afterEffects;
  if (film == null || params.filmAmount <= 0) {
    afterEffects = await _runPostDehaze(afterTone, width, height, params);
  } else {
    // Film after Grain, exactly where render.dart's applyGlobalPointOps
    // applies it on the CPU. Its own pass rather than a sampler on
    // post_dehaze.frag so a render with no film pays nothing for it.
    final beforeFilm = chain.add(
      await _runPostDehaze(afterTone, width, height, params),
    );
    final filmTexture = chain.add(await _buildFilmLutImage(film));
    afterEffects = await GpuPass.run(
      'shaders/film_lut.frag',
      floats: [
        width.toDouble(),
        height.toDouble(),
        params.filmAmount,
        film.size.toDouble(),
      ],
      samplers: [beforeFilm, filmTexture],
      outputWidth: width,
      outputHeight: height,
    );
  }
  final replace = params.replaceColor;
  if (replace.isIdentity) {
    chain.disposeAllExcept();
    return afterEffects;
  }
  // Replace color last of all (replace_color.dart), same as the CPU.
  final beforeReplace = chain.add(afterEffects);
  final result = await GpuPass.run(
    'shaders/replace_color.frag',
    floats: [
      width.toDouble(),
      height.toDouble(),
      replace.r / 255.0,
      replace.g / 255.0,
      replace.b / 255.0,
      replace.coreDistance,
      replace.featherDistance,
      replace.hue,
      1.0 + replace.saturation.clamp(-100.0, 100.0) / 100.0,
      1.0 + replace.luminance.clamp(-100.0, 100.0) / 100.0,
      replace.amount.clamp(0.0, 100.0) / 100.0,
    ],
    samplers: [beforeReplace],
    outputWidth: width,
    outputHeight: height,
  );
  chain.disposeAllExcept();
  return result;
}

/// The film table as the `size*size` x `size` RGBA texture
/// `film_lut.frag` samples — `FilmLut.packedRgba`'s layout, uploaded as
/// is. Built per render like the curve LUT; ~140 KB for the bundled 33^3
/// tables, well under what a pass costs.
Future<ui.Image> _buildFilmLutImage(FilmLut lut) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    lut.packedRgba(),
    lut.size * lut.size,
    lut.size,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

Future<ui.Image> _runPreDenoise(
  ui.Image source,
  int width,
  int height,
  RenderParams params,
) async {
  final program = await GpuPass.loadProgram(
    'shaders/point_ops_pre_denoise.frag',
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

  return _rasterize(shader, width, height, 'point_ops_pre_denoise');
}

Future<ui.Image> _runPostDenoise(
  ui.Image source,
  ui.Image lut,
  ui.Image? tonalBlur,
  int width,
  int height,
  RenderParams params,
) async {
  final program = await GpuPass.loadProgram(
    'shaders/point_ops_post_denoise.frag',
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
  // Centres then widths, matching uMixerBands[16]'s own halves.
  for (final centre in calMixerBandCentres) {
    shader.setFloat(i++, centre);
  }
  for (final width in calMixerBandWidths) {
    shader.setFloat(i++, width);
  }
  shader.setFloat(i++, calMixerBandNormalisation);
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

  return _rasterize(shader, width, height, 'point_ops_post_denoise');
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
  final program = await GpuPass.loadProgram('shaders/post_dehaze.frag');
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
  shader.setFloat(
    i++,
    (1.0 + params.saturation / 100.0 * calSaturationStrength) *
        (1.0 + params.saturationBoost * calCameraColorBoost),
  );
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

  return _rasterize(shader, width, height, 'post_dehaze');
}

Future<ui.Image> _rasterize(
  ui.FragmentShader shader,
  int width,
  int height,
  String debugLabel,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..shader = shader,
  );
  final picture = recorder.endRecording();
  GpuPass.countPass(debugLabel);
  // Same reasoning as GpuPass.run: the picture and the shader hold native
  // resources that only an explicit dispose releases, and both are dead
  // once the image exists.
  final image = await picture.toImage(width, height);
  picture.dispose();
  shader.dispose();
  return image;
}

/// The identity LUT texture's bytes (every channel `i` at texel `i`),
/// built once: the shader always samples `uLut`, so the no-curve case —
/// most renders — needs a texture too, just not a computed one.
final Uint8List _identityLutBytes = Uint8List.fromList([
  for (var i = 0; i < 256; i++) ...[i, i, i, 255],
]);

/// Builds the 256x1 RGBA LUT texture consumed by
/// `point_ops_post_denoise.frag`'s `uLut`: r/g/b = the whole curve stack
/// (parametric → point Tone Curve → that channel's colour curve) for the
/// red/green/blue channel, from `tone_curve.dart`'s
/// [buildCurveStackLuts] — the same numbers the CPU pass applies, composed
/// in double precision and rounded to a byte once here, where the texture
/// has to be 8-bit anyway. Until 2026-09-10 the texture held the curves
/// separately and composed them as chained byte lookups (`tone[param[i]]`
/// on the Dart side, then the tone and colour lookups in the shader), one
/// rounding per curve.
Future<ui.Image> _buildLutImage(
  PhotoCurves curves,
  ParametricCurve parametric,
) async {
  final luts = buildCurveStackLuts(parametric: parametric, curves: curves);
  final Uint8List bytes;
  if (luts == null) {
    bytes = _identityLutBytes;
  } else {
    bytes = Uint8List(256 * 4);
    for (var x = 0; x < 256; x++) {
      bytes[x * 4] = luts[0][x].round();
      bytes[x * 4 + 1] = luts[1][x].round();
      bytes[x * 4 + 2] = luts[2][x].round();
      bytes[x * 4 + 3] = 255;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(bytes, 256, 1, ui.PixelFormat.rgba8888, (image) {
    completer.complete(image);
  });
  return completer.future;
}
