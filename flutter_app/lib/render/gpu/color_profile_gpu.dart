import 'dart:ui' as ui;

import '../color_profile.dart';
import 'gpu_pass.dart';

/// GPU port of `color_profile.dart`'s `applyColorProfile` — per-hue half
/// only (`hueShift`/`satMul`/`lumMul`). Every profile shipped so far has
/// an identity tone curve by design, so this covers the full effect in
/// practice; a caller with a non-identity tone curve must still fall back
/// to the CPU path (see `editor_screen.dart`'s `_runRenderJob`).
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.
Future<ui.Image> runColorProfileGpu(
  ui.Image source,
  int width,
  int height,
  ColorProfile profile,
  double strength,
) async {
  if (strength <= 0) {
    return source;
  }
  var perHueActive = false;
  for (var i = 0; i < colorProfileBins; i++) {
    if (profile.hueShift[i] != 0 ||
        profile.satMul[i] != 1.0 ||
        profile.lumMul[i] != 1.0) {
      perHueActive = true;
      break;
    }
  }
  if (!perHueActive) {
    return source;
  }

  return GpuPass.run(
    'shaders/color_profile.frag',
    floats: [
      width.toDouble(),
      height.toDouble(),
      strength.clamp(0.0, 1.0),
      ...profile.hueShift,
      ...profile.satMul,
      ...profile.lumMul,
    ],
    samplers: [source],
    outputWidth: width,
    outputHeight: height,
  );
}
