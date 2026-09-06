import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../color_profile.dart';
import 'gpu_pass.dart';

/// GPU port of `render.dart`'s `applyColorProfileStage` — the fixed
/// "profile" contrast S-curve ([baseContrastGamma], `_applyBaseContrast`),
/// then `applyColorProfile` in full: its tone curve and then its per-hue
/// `hueShift`/`satMul`/`lumMul` correction, in that order.
///
/// The tone curve arrived here on 2026-09-04. Before that this pass
/// covered only the per-hue half and `editor_screen.dart`'s
/// `_runRenderJob` forced the whole render onto the CPU for any profile
/// carrying a real curve — harmless only because every built-in profile
/// sets tone to identity by design, and not harmless at all once users
/// can author their own.
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
  final toneActive = profile != null && strength > 0 && !profile.toneIsIdentity;
  if (!perHueActive && !toneActive && baseContrastGamma == 1.0) {
    return source;
  }

  // The shader declares uToneLut unconditionally, so something has to be
  // bound even when the curve is inactive. The identity ramp is cached
  // once and costs nothing to reuse.
  final toneLut = await _toneLutImage(
    toneActive ? profile.tone : identityColorProfile.tone,
  );

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
      toneActive ? 1.0 : 0.0,
    ],
    samplers: [source, toneLut],
    outputWidth: width,
    outputHeight: height,
  );
}

/// One-entry cache of the uploaded tone-curve texture, keyed by the curve
/// it was built from.
///
/// The profile changes when the user picks a different one — rarely — while
/// this pass runs on every render, so rebuilding and re-uploading a texture
/// each time would be pure churn of exactly the kind
/// project_perf_memory_overhaul_sep3.md went and removed. The cached image
/// is owned here and disposed when it is replaced; it is passed to
/// [GpuPass.run] as an input, never handed to a [GpuImagePool], so nothing
/// else will dispose it underneath this cache.
List<double>? _cachedToneKey;
ui.Image? _cachedToneImage;

Future<ui.Image> _toneLutImage(List<double> tone) async {
  final cached = _cachedToneImage;
  if (cached != null && _listEquals(_cachedToneKey, tone)) {
    return cached;
  }

  // 33x1 RGBA, one texel per tone point, the value split 16-bit across
  // r (high byte) and g (low byte).
  final bytes = Uint8List(colorProfileTonePoints * 4);
  for (var i = 0; i < colorProfileTonePoints; i++) {
    final v = (tone[i].clamp(0.0, 1.0) * 65535.0).round().clamp(0, 65535);
    bytes[i * 4] = (v >> 8) & 0xFF;
    bytes[i * 4 + 1] = v & 0xFF;
    bytes[i * 4 + 3] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    colorProfileTonePoints,
    1,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;

  cached?.dispose();
  _cachedToneImage = image;
  _cachedToneKey = List<double>.of(tone);
  return image;
}

bool _listEquals(List<double>? a, List<double> b) {
  if (a == null || a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// Drops the cached tone texture — for tests, which otherwise leak a
/// `ui.Image` across cases and can hide a stale-cache bug behind a hit
/// that happened to be correct.
void debugResetColorProfileGpuCache() {
  _cachedToneImage?.dispose();
  _cachedToneImage = null;
  _cachedToneKey = null;
}
