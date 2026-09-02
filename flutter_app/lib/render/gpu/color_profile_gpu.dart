import 'dart:ui' as ui;

import '../color_profile.dart';
import 'gpu_pass.dart';

/// GPU port of `render.dart`'s `applyColorProfileStage` — the fixed
/// "profile" contrast S-curve ([baseContrastGamma], `_applyBaseContrast`)
/// immediately followed by the per-hue correction (`applyColorProfile`'s
/// `hueShift`/`satMul`/`lumMul` half only — every profile shipped so far
/// has an identity tone curve by design, so this covers the full effect
/// in practice; a caller with a non-identity tone curve must still fall
/// back to the CPU path, see `editor_screen.dart`'s `_runRenderJob`).
///
/// [profile] is nullable (unlike the per-hue-only port this replaced,
/// 2026-09-02): Default mode has no per-hue profile at all but still has
/// a real, non-1.0 [baseContrastGamma] from its own `calBaseContrast`, so
/// this pass has to run for it too — real GPU/CPU order bug fixed the
/// same day: `_applyBaseContrast` runs immediately before Dehaze on CPU,
/// but the GPU equivalent used to live inside the big post-Dehaze
/// point-ops shader instead. Skips entirely only when there is truly
/// nothing to do (gamma is a no-op AND no active per-hue table).
///
/// **Must run on the main isolate** — see `render_gpu.dart`'s doc comment.
Future<ui.Image> runColorProfileGpu(
  ui.Image source,
  int width,
  int height,
  ColorProfile? profile,
  double strength,
  double baseContrastGamma,
) async {
  var perHueActive = false;
  if (profile != null && strength > 0) {
    for (var i = 0; i < colorProfileBins; i++) {
      if (profile.hueShift[i] != 0 ||
          profile.satMul[i] != 1.0 ||
          profile.lumMul[i] != 1.0) {
        perHueActive = true;
        break;
      }
    }
  }
  if (!perHueActive && baseContrastGamma == 1.0) {
    return source;
  }

  return GpuPass.run(
    'shaders/color_profile.frag',
    floats: [
      width.toDouble(),
      height.toDouble(),
      baseContrastGamma,
      strength.clamp(0.0, 1.0),
      ...(perHueActive ? profile!.hueShift : identityColorProfile.hueShift),
      ...(perHueActive ? profile!.satMul : identityColorProfile.satMul),
      ...(perHueActive ? profile!.lumMul : identityColorProfile.lumMul),
    ],
    samplers: [source],
    outputWidth: width,
    outputHeight: height,
  );
}
