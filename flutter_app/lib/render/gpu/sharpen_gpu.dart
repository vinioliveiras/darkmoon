import 'dart:ui' as ui;

import '../calibration.dart';
import '../sharpen.dart';
import 'gpu_pass.dart';

/// GPU port of `sharpen.dart`'s `applySharpen` — see
/// `project_gpu_render_plan.md`'s Phase 4. Unlike the CPU function, which
/// skips computing `fineBlurred`/`edgeStrength`/`localNoiseVar` entirely
/// when `detail`/`masking` are 0 (via `Float32List?` null checks), this
/// always computes them and lets `sharpen_combine.frag`'s uDetailMix/
/// uMaskAmount naturally zero out their contribution — see that shader's
/// doc comment for why this is a safe, output-identical simplification
/// here (unlike Texture/Clarity, which need real flag uniforms).
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.
Future<ui.Image> runSharpenGpu(
  ui.Image source,
  int width,
  int height,
  SharpenParams params,
) async {
  if (params.isIdentity) {
    return source;
  }

  final sigma = params.radius.clamp(0.5, 3.0);
  final strength = params.amount / 100.0 * calSharpenStrength;
  final detailMix = params.detail / 100.0;
  final maskAmount = params.masking / 100.0;

  final luminance = await GpuPass.run(
    'shaders/luminance_extract.frag',
    floats: [width.toDouble(), height.toDouble()],
    samplers: [source],
    outputWidth: width,
    outputHeight: height,
  );
  final blurred = await runGaussianBlurGpu(luminance, width, height, sigma);
  final fineBlurred = await runGaussianBlurGpu(
    luminance,
    width,
    height,
    sigma * 0.5,
  );

  final absResidual = await GpuPass.run(
    'shaders/abs_residual.frag',
    floats: [width.toDouble(), height.toDouble()],
    samplers: [luminance, blurred],
    outputWidth: width,
    outputHeight: height,
  );
  final edgeStrength = await runGaussianBlurGpu(
    absResidual,
    width,
    height,
    sigma,
  );

  final residualSq = await GpuPass.run(
    'shaders/residual_sq.frag',
    floats: [width.toDouble(), height.toDouble(), 0.0],
    samplers: [luminance, blurred],
    outputWidth: width,
    outputHeight: height,
  );
  final noiseVar = await runBoxBlurGpu(residualSq, width, height, 6);

  return GpuPass.run(
    'shaders/sharpen_combine.frag',
    floats: [
      width.toDouble(),
      height.toDouble(),
      strength,
      detailMix,
      maskAmount,
    ],
    samplers: [source, luminance, blurred, fineBlurred, edgeStrength, noiseVar],
    outputWidth: width,
    outputHeight: height,
  );
}
