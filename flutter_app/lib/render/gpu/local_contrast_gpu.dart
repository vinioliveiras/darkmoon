import 'dart:ui' as ui;

import 'gpu_pass.dart';

/// GPU port of `local_contrast.dart`'s `applyLocalContrast` — shared by
/// Texture (sigma=3, [noiseAware]) and Clarity (sigma=25,
/// [protectMidtones]), matching the CPU side's single shared function. See
/// `project_gpu_render_plan.md`'s Phase 4.
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
}) async {
  if (amount == 0) {
    return source;
  }

  final scratch = GpuImagePool();
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
    await runGaussianBlurGpu(luminance, width, height, sigma),
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
