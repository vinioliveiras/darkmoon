import 'dart:ui' as ui;

import '../calibration.dart';
import '../sharpen.dart';
import 'gpu_pass.dart';

/// GPU port of `sharpen.dart`'s `applySharpen` — see
/// `project_gpu_render_plan.md`'s Phase 4.
///
/// The masking half (`edgeStrength` + `noiseVar`) is skipped when
/// `masking` is 0, matching what the CPU function already did with its
/// `Float32List?` null checks. This used to compute them unconditionally
/// and let `sharpen_combine.frag`'s uMaskAmount zero their contribution —
/// "a safe, output-identical simplification". Output-identical it was;
/// free it was not. Sharpen runs on every photo (`amount` defaults to 40,
/// Meridian's own RAW-import default) while `masking` defaults to 0, so
/// that simplification spent five full-resolution passes per render — a
/// measured ~120ms of a ~500ms neutral 6 MP render — on values that were
/// then multiplied by zero.
///
/// `fineBlurred` stays unconditional: `detail` defaults to 25, so it is
/// genuinely needed on a default render, and gating it would only pay off
/// for a user who deliberately set detail to 0.
///
/// `sharpen_combine.frag` needs every sampler bound regardless, so the
/// skipped ones are bound to `blurred` as an inert stand-in — the same
/// placeholder trick `local_contrast_gpu.dart` uses for its own
/// noise-variance sampler.
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
  final fineBlurred = scratch.add(
    await runGaussianBlurGpu(luminance, width, height, sigma * 0.5),
  );

  // Both of these feed the edge mask only, which uMaskAmount switches off
  // entirely at 0 — see this function's doc comment.
  var edgeStrength = blurred;
  var noiseVar = blurred;
  if (maskAmount > 0) {
    final absResidual = scratch.add(
      await GpuPass.run(
        'shaders/abs_residual.frag',
        floats: [width.toDouble(), height.toDouble()],
        samplers: [luminance, blurred],
        outputWidth: width,
        outputHeight: height,
      ),
    );
    edgeStrength = scratch.add(
      await runGaussianBlurGpu(absResidual, width, height, sigma),
    );

    final residualSq = scratch.add(
      await GpuPass.run(
        'shaders/residual_sq.frag',
        floats: [width.toDouble(), height.toDouble(), 0.0, gpuResidualSqScale],
        samplers: [luminance, blurred],
        outputWidth: width,
        outputHeight: height,
      ),
    );
    noiseVar = scratch.add(await runBoxBlurGpu(residualSq, width, height, 6));
  }

  final edgeThreshold = calSharpenEdgeThreshold / 255.0;
  final edgeThresholdVar = edgeThreshold * edgeThreshold;
  final result = await GpuPass.run(
    'shaders/sharpen_combine.frag',
    floats: [
      width.toDouble(),
      height.toDouble(),
      strength,
      detailMix,
      maskAmount,
      calSharpenDetailMix,
      edgeThresholdVar,
      gpuResidualSqScale,
    ],
    samplers: [source, luminance, blurred, fineBlurred, edgeStrength, noiseVar],
    outputWidth: width,
    outputHeight: height,
  );
  scratch.disposeAllExcept();
  return result;
}
