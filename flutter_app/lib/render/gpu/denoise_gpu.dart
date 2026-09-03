import 'dart:ui' as ui;

import '../ai_denoise.dart';
import '../blur.dart' show scaledNoiseRadius;
import '../calibration.dart';
import 'gpu_pass.dart';

/// GPU counterpart to `baseline_chroma.dart`/`ai_denoise.dart` — see
/// `project_gpu_render_plan.md`'s Phase 3. Both CPU functions are built on
/// the same `adaptiveDenoiseChannel` primitive (`blur.dart`); this file's
/// [_runAdaptiveDenoise] is its GPU port, shared by both
/// [runBaselineChromaSmoothingGpu] and [runAiDenoiseGpu] below the same way
/// the CPU functions share `adaptiveDenoiseChannel`.
///
/// Chroma values are signed (~[-1,1] in this pipeline's 0..1-normalized
/// working space) but 8-bit render targets can't hold negative values —
/// every chroma texture here is bias/scale-*encoded* (`chroma*0.5+0.5`,
/// see `shaders/chroma_extract.frag`'s doc comment) and only decoded where
/// a shader does real math on it. `isChroma` parameters below select that
/// encoding; luminance textures need no such handling (already plain 0..1).
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.

/// How much smaller (per dimension) baseline chroma smoothing denoises
/// chroma at — matches `baseline_chroma.dart`'s `_downsampleFactor`.
const int _chromaDownsampleFactor = 4;

/// Matches `baseline_chroma.dart`'s hardcoded sigma/strength constants.
const double _baselineChromaSigma = 2.5;
const double _baselineChromaStrength = 0.4;

/// GPU port of `blur.dart`'s `adaptiveDenoiseChannel` — the Wiener-style
/// soft-threshold blend shared by baseline chroma smoothing and AI
/// denoise. [channel] may be a luminance texture ([isChroma] false) or a
/// `chroma_extract.frag`-encoded chroma texture ([isChroma] true).
Future<ui.Image> _runAdaptiveDenoise(
  ui.Image channel,
  int width,
  int height,
  double sigma,
  double strength, {
  bool isChroma = false,
  int noiseRadius = 6,
}) async {
  if (strength <= 0) {
    return channel;
  }
  final scratch = GpuImagePool([channel]);
  final blurred = scratch.add(
    await runGaussianBlurGpu(channel, width, height, sigma),
  );
  final residualSq = scratch.add(
    await GpuPass.run(
      'shaders/residual_sq.frag',
      floats: [
        width.toDouble(),
        height.toDouble(),
        isChroma ? 1.0 : 0.0,
        gpuResidualSqScale,
      ],
      samplers: [channel, blurred],
      outputWidth: width,
      outputHeight: height,
    ),
  );
  var noiseVar = scratch.add(
    await GpuPass.run(
      'shaders/box_blur_h.frag',
      floats: [width.toDouble(), height.toDouble(), noiseRadius.toDouble()],
      samplers: [residualSq],
      outputWidth: width,
      outputHeight: height,
    ),
  );
  noiseVar = scratch.add(
    await GpuPass.run(
      'shaders/box_blur_v.frag',
      floats: [width.toDouble(), height.toDouble(), noiseRadius.toDouble()],
      samplers: [noiseVar],
      outputWidth: width,
      outputHeight: height,
    ),
  );
  final result = await GpuPass.run(
    'shaders/denoise_combine.frag',
    floats: [
      width.toDouble(),
      height.toDouble(),
      isChroma ? 1.0 : 0.0,
      strength,
      gpuResidualSqScale,
    ],
    samplers: [channel, blurred, noiseVar],
    outputWidth: width,
    outputHeight: height,
  );
  // [channel] belongs to the caller and was never registered here.
  scratch.disposeAllExcept();
  return result;
}

/// GPU port of `baseline_chroma.dart`'s `applyBaselineChromaSmoothing` —
/// the always-on, no-slider chroma smoothing pass. Unlike the CPU version,
/// there's no small-image fallback (CPU denoises at full resolution below
/// `_downsampleFactor*3` px) — not implemented here since real photos and
/// GPU test buffers are always comfortably larger than that; would need
/// adding if this is ever fed a tiny image directly.
/// [scale] is [RenderParams.renderScale] — this stage has no slider but is
/// still a fixed-pixel blur, so it has to grow with the frame like every
/// other one. See `calibration.dart`'s `calRadiusReferenceLongEdge`.
Future<ui.Image> runBaselineChromaSmoothingGpu(
  ui.Image source,
  int width,
  int height, [
  double scale = 1.0,
]) async {
  final scratch = GpuImagePool([source]);
  final chroma = scratch.add(
    await GpuPass.run(
      'shaders/chroma_extract.frag',
      floats: [width.toDouble(), height.toDouble()],
      samplers: [source],
      outputWidth: width,
      outputHeight: height,
    ),
  );

  final smallWidth = (width / _chromaDownsampleFactor).ceil();
  final smallHeight = (height / _chromaDownsampleFactor).ceil();
  final small = scratch.add(
    await GpuPass.run(
      'shaders/downsample_box.frag',
      floats: [
        smallWidth.toDouble(),
        smallHeight.toDouble(),
        width.toDouble(),
        height.toDouble(),
        _chromaDownsampleFactor.toDouble(),
      ],
      samplers: [chroma],
      outputWidth: smallWidth,
      outputHeight: smallHeight,
    ),
  );

  final denoisedSmall = scratch.add(
    await _runAdaptiveDenoise(
      small,
      smallWidth,
      smallHeight,
      _baselineChromaSigma * scale / _chromaDownsampleFactor,
      _baselineChromaStrength,
      isChroma: true,
      // Applied at the downsampled resolution, so the base stays the 6
      // this pass has always used and only renderScale multiplies it.
      noiseRadius: scaledNoiseRadius(scale),
    ),
  );

  final denoisedChroma = scratch.add(
    await GpuPass.run(
      'shaders/upsample.frag',
      floats: [
        width.toDouble(),
        height.toDouble(),
        smallWidth.toDouble(),
        smallHeight.toDouble(),
        _chromaDownsampleFactor.toDouble(),
      ],
      samplers: [denoisedSmall],
      outputWidth: width,
      outputHeight: height,
    ),
  );

  final result = await GpuPass.run(
    'shaders/chroma_recombine.frag',
    floats: [width.toDouble(), height.toDouble()],
    samplers: [source, denoisedChroma],
    outputWidth: width,
    outputHeight: height,
  );
  scratch.disposeAllExcept();
  return result;
}

/// GPU port of `ai_denoise.dart`'s `applyAiDenoise` — the one-shot AI
/// Denoise toolbar action's classical (non-neural) algorithm. Returns
/// [source] unchanged when [params] is off, matching the CPU function's
/// own early return.
/// [scale] is [RenderParams.renderScale] — the per-level sigmas are quoted
/// in pixels. See `calibration.dart`'s `calRadiusReferenceLongEdge`.
Future<ui.Image> runAiDenoiseGpu(
  ui.Image source,
  int width,
  int height,
  AiDenoiseParams params, [
  double scale = 1.0,
]) async {
  final level = params.level;
  if (level == null) {
    return source;
  }
  final tuning = aiDenoiseTuning[level]!;
  // calibration.dart global scale on top of the per-level table — matches
  // ai_denoise.dart's applyAiDenoise exactly (real bug found 2026-09-03:
  // this scale was never applied on GPU at all, only the raw table value).
  final lumaStrength = (tuning.lumaStrength * calDenoiseLumaStrengthScale)
      .clamp(0.0, 1.0);
  final chromaStrength = (tuning.chromaStrength * calDenoiseChromaStrengthScale)
      .clamp(0.0, 1.0);

  final scratch = GpuImagePool([source]);
  final luminance = scratch.add(
    await GpuPass.run(
      'shaders/luminance_extract.frag',
      floats: [width.toDouble(), height.toDouble()],
      samplers: [source],
      outputWidth: width,
      outputHeight: height,
    ),
  );
  final chroma = scratch.add(
    await GpuPass.run(
      'shaders/chroma_extract.frag',
      floats: [width.toDouble(), height.toDouble()],
      samplers: [source],
      outputWidth: width,
      outputHeight: height,
    ),
  );

  final denoisedLuma = scratch.add(
    await _runAdaptiveDenoise(
      luminance,
      width,
      height,
      tuning.lumaSigma * scale,
      lumaStrength,
      noiseRadius: scaledNoiseRadius(scale),
    ),
  );
  final denoisedChroma = scratch.add(
    await _runAdaptiveDenoise(
      chroma,
      width,
      height,
      tuning.chromaSigma * scale,
      chromaStrength,
      isChroma: true,
      noiseRadius: scaledNoiseRadius(scale),
    ),
  );

  final result = await GpuPass.run(
    'shaders/luma_chroma_recombine.frag',
    floats: [width.toDouble(), height.toDouble()],
    samplers: [denoisedLuma, denoisedChroma],
    outputWidth: width,
    outputHeight: height,
  );
  scratch.disposeAllExcept();
  return result;
}
