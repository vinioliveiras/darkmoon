import 'dart:ui' as ui;

import '../blur.dart' show guidedRadiusForSigma;
import '../calibration.dart';
import 'gpu_pass.dart';

/// GPU port of `dehaze.dart`'s `applyDehaze` — see that function's own doc
/// comment for the algorithm (a port of Solstice's `apply_dehaze`). Unlike
/// the previous atmospheric-light-estimation-based version, this needs no
/// CPU readback at all: the atmospheric light Solstice uses is a fixed
/// constant, so the whole effect is one wide Gaussian blur pass (the
/// "regional" dark-channel source, matching Solstice's own
/// structure_blur_view) plus one per-pixel apply pass, both fully on GPU.
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.
/// [scale] is [RenderParams.renderScale] — the sigma-40 "regional" blur is
/// a fixed pixel radius, so it has to grow with the frame. See
/// `calibration.dart`'s `calRadiusReferenceLongEdge`. [edgeThreshold] > 0
/// makes that blur edge-preserving ([runGuidedSmoothGpu]), as on the CPU
/// side — see `applyDehaze`'s doc comment.
Future<ui.Image> runDehazeGpu(
  ui.Image source,
  int width,
  int height,
  double amount, [
  double scale = 1.0,
  double edgeThreshold = calDehazeEdgeThreshold,
]) async {
  if (amount == 0) {
    return source;
  }
  final strength = amount / 100.0;
  final sigma = 40.0 * scale;
  final blurred = edgeThreshold > 0
      ? await runGuidedSmoothGpu(
          source,
          width,
          height,
          guidedRadiusForSigma(sigma),
          edgeThreshold / 255.0,
        )
      : await runGaussianBlurGpu(source, width, height, sigma);

  final result = await GpuPass.run(
    'shaders/dehaze_apply.frag',
    floats: [
      width.toDouble(),
      height.toDouble(),
      strength,
      calDehazeTransmissionCoeff,
      calDehazeTransmissionFloor,
      calDehazeSatBoost,
      calDehazeAddMix,
    ],
    samplers: [source, blurred],
    outputWidth: width,
    outputHeight: height,
  );
  // Not necessarily a new image: runGaussianBlurGpu hands its input
  // straight back when every box radius rounds to zero, and [source]
  // belongs to the caller.
  if (!identical(blurred, source)) {
    blurred.dispose();
  }
  return result;
}
