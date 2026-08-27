import 'dart:ui' as ui;

import 'gpu_pass.dart';

/// GPU port of `dehaze.dart`'s `applyDehaze` — see that function's own doc
/// comment for the algorithm (a port of RapidRAW's `apply_dehaze`). Unlike
/// the previous atmospheric-light-estimation-based version, this needs no
/// CPU readback at all: the atmospheric light RapidRAW uses is a fixed
/// constant, so the whole effect is one wide Gaussian blur pass (the
/// "regional" dark-channel source, matching RapidRAW's own
/// structure_blur_view) plus one per-pixel apply pass, both fully on GPU.
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.
Future<ui.Image> runDehazeGpu(
  ui.Image source,
  int width,
  int height,
  double amount,
) async {
  if (amount == 0) {
    return source;
  }
  final strength = amount / 100.0;
  final blurred = await runGaussianBlurGpu(source, width, height, 40.0);

  return GpuPass.run(
    'shaders/dehaze_apply.frag',
    floats: [width.toDouble(), height.toDouble(), strength],
    samplers: [source, blurred],
    outputWidth: width,
    outputHeight: height,
  );
}
