import 'dart:ui' as ui;

import 'dart:math' as math;

import '../blur.dart' show guidedRadiusForSigma, guidedSubsampleFactor;
import 'gpu_pass.dart';

/// GPU port of `local_contrast.dart`'s `applyLocalContrast` — shared by
/// Texture (sigma=3, [noiseAware]) and Clarity (sigma=25,
/// [protectMidtones]), matching the CPU side's single shared function. See
/// `project_gpu_render_plan.md`'s Phase 4.
///
/// [edgeThreshold] > 0 (Clarity) replaces the Gaussian base with the
/// edge-preserving one of `blur.dart`'s `guidedSmoothChannel` — see
/// [_guidedBase].
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.
Future<ui.Image> runLocalContrastGpu(
  ui.Image source,
  int width,
  int height,
  double amount,
  double sigma, {
  bool protectMidtones = false,
  bool noiseAware = false,
  int noiseRadius = 6,
  double edgeThreshold = 0,
}) async {
  if (amount == 0) {
    return source;
  }

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
  final blurred = scratch.add(
    edgeThreshold > 0
        ? await _guidedBase(
            luminance,
            width,
            height,
            guidedRadiusForSigma(sigma),
            edgeThreshold / 255.0,
          )
        : await runGaussianBlurGpu(luminance, width, height, sigma),
  );

  // Always computed (cheap relative to the blur chain above) rather than
  // gated on `noiseAware`, since local_contrast_combine.frag's uNoiseVar
  // sampler needs a bound image regardless — `blurred` is only ever
  // substituted as an unused placeholder when `noiseAware` is off.
  ui.Image noiseVar;
  if (noiseAware) {
    final residualSq = scratch.add(
      await GpuPass.run(
        'shaders/residual_sq.frag',
        floats: [width.toDouble(), height.toDouble(), 0.0, gpuResidualSqScale],
        samplers: [luminance, blurred],
        outputWidth: width,
        outputHeight: height,
      ),
    );
    noiseVar = scratch.add(
      await runBoxBlurGpu(residualSq, width, height, noiseRadius),
    );
  } else {
    noiseVar = blurred;
  }

  final result = await GpuPass.run(
    'shaders/local_contrast_combine.frag',
    floats: [
      width.toDouble(),
      height.toDouble(),
      amount / 100.0,
      protectMidtones ? 1.0 : 0.0,
      noiseAware ? 1.0 : 0.0,
      gpuResidualSqScale,
    ],
    samplers: [source, luminance, blurred, noiseVar],
    outputWidth: width,
    outputHeight: height,
  );
  scratch.disposeAllExcept();
  return result;
}

/// GPU port of `guidedSmoothChannel`: mean and mean absolute deviation
/// of [luminance] over a box of [radius], the per-pixel `a`/`b` fit
/// (guided_ab.frag, packed as one RG image so a single box blur averages
/// both), and `q = mean(a)·I + mean(b)` (guided_apply.frag). Past
/// `guidedMaxFullResRadius` the fit runs on a copy downsampled by
/// [guidedSubsampleFactor] — the same shaders and factor rule the pyramid
/// blur in gpu_pass.dart uses, and the same copy the CPU side fits on —
/// and the averaged (a, b) pair is upsampled back for the final pass.
/// [threshold] is calClarityEdgeThreshold on this side's 0..1 scale.
Future<ui.Image> _guidedBase(
  ui.Image luminance,
  int width,
  int height,
  int radius,
  double threshold,
) async {
  final scratch = GpuImagePool([luminance]);
  final factor = guidedSubsampleFactor(radius);
  var work = luminance;
  var w = width;
  var h = height;
  var r = radius;
  if (factor > 1) {
    w = math.max(1, (width / factor).ceil());
    h = math.max(1, (height / factor).ceil());
    r = math.max(1, (radius / factor).round());
    work = scratch.add(
      await GpuPass.run(
        'shaders/downsample_box.frag',
        floats: [
          w.toDouble(),
          h.toDouble(),
          width.toDouble(),
          height.toDouble(),
          factor.toDouble(),
        ],
        samplers: [luminance],
        outputWidth: w,
        outputHeight: h,
      ),
    );
  }
  final size = [w.toDouble(), h.toDouble()];
  final mean = scratch.add(await runBoxBlurGpu(work, w, h, r));
  final dev = scratch.add(
    await GpuPass.run(
      'shaders/abs_residual.frag',
      floats: size,
      samplers: [work, mean],
      outputWidth: w,
      outputHeight: h,
    ),
  );
  final mad = scratch.add(await runBoxBlurGpu(dev, w, h, r));
  final ab = scratch.add(
    await GpuPass.run(
      'shaders/guided_ab.frag',
      floats: [...size, threshold],
      samplers: [mean, mad],
      outputWidth: w,
      outputHeight: h,
    ),
  );
  var meanAb = scratch.add(await runBoxBlurGpu(ab, w, h, r));
  if (factor > 1) {
    meanAb = scratch.add(
      await GpuPass.run(
        'shaders/upsample.frag',
        floats: [
          width.toDouble(),
          height.toDouble(),
          w.toDouble(),
          h.toDouble(),
          factor.toDouble(),
        ],
        samplers: [meanAb],
        outputWidth: width,
        outputHeight: height,
      ),
    );
  }
  final result = await GpuPass.run(
    'shaders/guided_apply.frag',
    floats: [width.toDouble(), height.toDouble()],
    samplers: [luminance, meanAb],
    outputWidth: width,
    outputHeight: height,
  );
  scratch.disposeAllExcept();
  return result;
}
