import 'dart:math' as math;
import 'dart:typed_data';

import 'ai_denoise.dart';
import 'baseline_chroma.dart';
import 'color_grading.dart';
import 'color_mixer.dart';
import 'dehaze.dart';
import 'local_contrast.dart';
import 'luminance.dart';
import 'mask.dart';
import 'render_params.dart';
import 'sharpen.dart';
import 'tone_curve.dart';
import 'vignette.dart';

/// Absolute color temperature (Kelvin) treated as "no white-balance shift",
/// matching the Python app's TEMPERATURE_NEUTRAL_KELVIN.
const double _temperatureNeutralKelvin = 5500.0;

/// Applies the tonal/color adjustment pipeline to packed 8-bit RGB pixel
/// data (3 bytes/pixel, row-major, no padding) and returns a new buffer of
/// the same shape.
///
/// This is a straight port of the Python app's `render()` — same order of
/// operations, same per-step math.
///
/// Designed to run via `compute()`: pure function over simple, isolate-
/// transferable data.
Uint8List renderRgb(
  int width,
  int height,
  Uint8List sourceRgb,
  RenderParams params, {
  void Function(RenderStage stage)? onStage,
}) {
  final buffer = Float32List(sourceRgb.length);
  for (var i = 0; i < sourceRgb.length; i++) {
    buffer[i] = sourceRgb[i].toDouble();
  }
  _applyAdjustmentSteps(buffer, width, height, params, onStage: onStage);
  return _toUint8(buffer);
}

/// Renders [sourceRgb] with [globalParams] as the base layer, then
/// composites each enabled mask in [masks] on top — each mask re-applies
/// its own [MaskLayer.values] over the buffer as it stands *after* the
/// previous layer (matching Lightroom/Photomator: masks stack, they
/// don't each start over from the untouched source), blended in using
/// that mask's own per-pixel alpha.
///
/// Designed to run via `compute()`: pure function over simple,
/// isolate-transferable data.
Uint8List renderRgbWithMasks(
  int width,
  int height,
  Uint8List sourceRgb,
  RenderParams globalParams,
  List<MaskLayer> masks,
) {
  final buffer = Float32List(sourceRgb.length);
  for (var i = 0; i < sourceRgb.length; i++) {
    buffer[i] = sourceRgb[i].toDouble();
  }
  _applyAdjustmentSteps(buffer, width, height, globalParams);

  for (final mask in masks) {
    // A mask with no adjustment values and an identity curve has nothing
    // to paint — skipping it avoids a full-buffer copy, a full re-run of
    // every adjustment step, and a per-pixel alpha computation for a
    // layer that would blend in as a no-op anyway. This matters in
    // practice: every enabled mask pays this cost on every render
    // (including drags of the global sliders or a different mask
    // entirely), so a photo with several masks — most of which are only
    // there for their geometry/opacity while the user tweaks something
    // else — would otherwise re-run the whole pipeline once per mask on
    // every single slider tick.
    if (!mask.enabled || (mask.values.isEmpty && mask.curves.isIdentity)) {
      continue;
    }
    final layerBuffer = Float32List.fromList(buffer);
    _applyAdjustmentSteps(
      layerBuffer,
      width,
      height,
      RenderParams.fromValues(mask.values, curves: mask.curves),
    );
    final alpha = computeMaskAlpha(
      mask,
      width,
      height,
      sourceForColorRange: buffer,
    );
    var p = 0;
    for (var pixel = 0; pixel < alpha.length; pixel++, p += 3) {
      final a = alpha[pixel];
      if (a <= 0) {
        continue;
      }
      if (a >= 1) {
        buffer[p] = layerBuffer[p];
        buffer[p + 1] = layerBuffer[p + 1];
        buffer[p + 2] = layerBuffer[p + 2];
        continue;
      }
      buffer[p] = buffer[p] * (1 - a) + layerBuffer[p] * a;
      buffer[p + 1] = buffer[p + 1] * (1 - a) + layerBuffer[p + 1] * a;
      buffer[p + 2] = buffer[p + 2] * (1 - a) + layerBuffer[p + 2] * a;
    }
  }

  return _toUint8(buffer);
}

/// The coarse stages [_applyAdjustmentSteps] moves through — used by
/// `render_job.dart`'s progress-reporting entry point for the one-shot AI
/// Denoise apply action, the slowest single step in the pipeline.
enum RenderStage { denoising, adjusting, encoding }

// Each constant below is a generous upper bound (not a tight measurement)
// on how many pixels beyond its own position one of [applyLocalAdjustmentSteps]'s
// blur-based stages can reach, derived from its box-blur radii (see
// `blur.dart`'s `_boxRadiiForGauss`) plus any local-variance window it
// layers on top. Padding a band by less than the true reach would blur in
// wrong (or missing/zero) data near the seam; padding by more only costs
// a little redundant computation, never correctness — so these round up.
const int _chromaSmoothingHaloPx =
    40; // always active, downsampled 4x internally
const int _sharpenHaloPx = 30; // radius up to 3.0 + a 6px noise window
const int _aiDenoiseHaloPx =
    50; // strong level's chromaSigma 5.0 + a 6px noise window
const int _textureHaloPx = 30; // fixed sigma 3 + a 6px noise window
const int _clarityHaloPx = 110; // fixed sigma 25 — the single biggest reach

/// How many extra rows a horizontal band needs on each side (above and
/// below the rows it's actually responsible for) before
/// [applyLocalAdjustmentSteps] runs on it, for the result to come out
/// pixel-identical to running that same function on the whole image at
/// once. Sums each active stage's own reach (see the constants above)
/// rather than taking their max, since they run in sequence — a later
/// stage can read pixels that an earlier stage already shifted using data
/// from beyond *its own* halo, so the margins compound outward.
///
/// Always includes [_chromaSmoothingHaloPx] (baseline chroma smoothing has
/// no on/off switch); the rest only count when that param is actually
/// active, so an untouched photo's halo stays small and most of a band's
/// height goes toward real parallel work instead of overlap.
int localAdjustmentHaloPx(RenderParams params) {
  var halo = _chromaSmoothingHaloPx;
  if (!params.sharpen.isIdentity) {
    halo += _sharpenHaloPx;
  }
  if (!params.aiDenoise.isIdentity) {
    halo += _aiDenoiseHaloPx;
  }
  if (params.texture != 0) {
    halo += _textureHaloPx;
  }
  if (params.clarity != 0) {
    halo += _clarityHaloPx;
  }
  return halo;
}

void _applyAdjustmentSteps(
  Float32List buffer,
  int width,
  int height,
  RenderParams params, {
  void Function(RenderStage stage)? onStage,
}) {
  onStage?.call(RenderStage.denoising);
  applyLocalAdjustmentSteps(buffer, width, height, params);
  onStage?.call(RenderStage.adjusting);
  applyGlobalAdjustmentSteps(buffer, width, height, params);
}

/// Every step whose effect on a pixel only ever depends on pixels within a
/// bounded distance of it (a fixed blur/box-filter radius, or nothing at
/// all) — as opposed to [applyGlobalAdjustmentSteps]'s Dehaze, which needs
/// a statistic computed from the *entire* image. That distinction is what
/// makes this half of the pipeline safe to run on an image split into
/// independent horizontal bands (see `render_parallel.dart`): as long as
/// each band is padded with at least [localAdjustmentHaloPx]'s worth of
/// extra rows on each side before this runs, and that padding is trimmed
/// off afterward, running this on each band separately and concatenating
/// the results is pixel-identical to running it on the whole image once.
///
/// Order matches the Python app's `render()` for this half of the
/// pipeline — see [applyGlobalAdjustmentSteps] for the rest.
///
/// [rowOffset] must be [buffer]'s row 0's absolute row index in the full
/// image when [buffer] is one band of a larger image being rendered by
/// `render_parallel.dart` (0, the default, for the whole image) — plumbed
/// straight through to [applyBaselineChromaSmoothing], the one step here
/// whose own internal downsampling needs it (see that function and
/// [downsampleChannel] for why).
void applyLocalAdjustmentSteps(
  Float32List buffer,
  int width,
  int height,
  RenderParams params, {
  int rowOffset = 0,
}) {
  final pixelCount = width * height;
  _applyWhiteBalance(buffer, params.temperature, params.tint);
  _applyExposure(buffer, params.exposure);
  // Denoise runs early — right after white balance/exposure establish the
  // pixel values but before any tone shaping — so Highlights/Shadows/
  // Whites/Blacks and Clarity/Texture don't push local contrast into noise
  // this pass never got a chance to remove. Doing it after tone shaping
  // (as an earlier version of this pipeline did) let a strong Shadows lift
  // amplify shadow-region noise right back up, undoing much of the
  // smoothing. Matches Lightroom's own ordering: its noise reduction is
  // one of the first things applied to the raw sensor data, well before
  // Basic panel tone adjustments.
  applyBaselineChromaSmoothing(buffer, width, height, rowOffset: rowOffset);
  applyAiDenoise(buffer, width, height, params.aiDenoise);
  _applyBrightnessContrast(buffer, params.brightness, params.contrast);
  _applyHighlightsShadows(
    buffer,
    pixelCount,
    params.highlights,
    params.shadows,
  );
  _applyWhitesBlacks(buffer, pixelCount, params.whites, params.blacks);
  applyToneCurve(buffer, params.curves.tone);
  applyColorCurves(
    buffer,
    params.curves.red,
    params.curves.green,
    params.curves.blue,
  );
  applyColorMixer(buffer, params.colorMixer);
  applyColorGrading(buffer, params.colorGrading);
  applySharpen(buffer, width, height, params.sharpen);
  applyLocalContrast(
    buffer,
    width,
    height,
    params.texture,
    3,
    noiseAware: true,
  );
  applyLocalContrast(
    buffer,
    width,
    height,
    params.clarity,
    25,
    protectMidtones: true,
  );
}

/// Everything [applyLocalAdjustmentSteps] leaves out — chiefly Dehaze,
/// which estimates atmospheric light from the 0.1% of *the whole image's*
/// pixels with the largest dark-channel value (`dehaze.dart`), a genuinely
/// global statistic no per-band halo could make correct; Vibrance/
/// Saturation/Vignette tag along here too since they're cheap enough
/// (low-hundreds-of-ms even at full sensor resolution, see the profiling
/// this pipeline split was built for) that splitting them out for
/// parallelism wouldn't be worth the added complexity. Must run after
/// [applyLocalAdjustmentSteps] on the *complete, already-stitched-back-
/// together* buffer — never per-band.
void applyGlobalAdjustmentSteps(
  Float32List buffer,
  int width,
  int height,
  RenderParams params,
) {
  final pixelCount = width * height;
  applyDehaze(buffer, width, height, params.dehaze);
  _applyVibrance(buffer, pixelCount, params.vibrance);
  _applySaturation(buffer, pixelCount, params.saturation);
  applyVignette(buffer, width, height, params.vignette);
}

Uint8List _toUint8(Float32List buffer) {
  final out = Uint8List(buffer.length);
  for (var i = 0; i < buffer.length; i++) {
    out[i] = buffer[i].clamp(0.0, 255.0).round();
  }
  return out;
}

/// How strongly a mired shift moves the red/blue gains — calibrated so the
/// overall warm/cool strength at typical daylight deltas roughly matches
/// the old Kelvin-linear model's feel around 5500K, while the mired scale
/// (rather than raw Kelvin) makes larger deviations track Lightroom's
/// actual Temp-slider curve instead of under- or over-correcting them.
const double _miredGainPerUnit = 0.0013;

void _applyWhiteBalance(
  Float32List img,
  double temperatureKelvin,
  double tint,
) {
  if (temperatureKelvin == _temperatureNeutralKelvin && tint == 0) {
    return;
  }
  // Color temperature correction is approximately linear in "mired"
  // (micro reciprocal degrees, 1e6/Kelvin) rather than in Kelvin itself —
  // the same reason photographic warming/cooling filters are rated in
  // mired shift, not Kelvin. A Kelvin-linear model (equal gain per Kelvin
  // regardless of starting point) badly under- or overshoots for presets
  // that set an absolute Temperature far from the 5500K reference, like a
  // warm-toned preset dropping to ~4200K, because the same Kelvin delta is
  // a much bigger perceptual/mired shift down in the warm end of the scale
  // than up in the cool end.
  //
  // This slider follows Lightroom/Camera Raw's own (famously
  // counter-intuitive) convention, also encoded in its blue->orange
  // gradient (editor_screen.dart's 'Temperature' _SliderSpec): the value
  // means "what Kelvin was the scene's actual light source", so *raising*
  // it tells the app the light was bluer than assumed, and the app adds
  // warmth to compensate — a *higher* Kelvin value renders *warmer*
  // (orange), a lower one renders cooler (blue). (This was previously
  // inverted here — verified against a real Canon 350D CR2 where raising
  // Temperature visibly cooled the image instead of warming it.)
  final miredDelta =
      1.0e6 / _temperatureNeutralKelvin - 1.0e6 / temperatureKelvin;
  final tempGain = (miredDelta * _miredGainPerUnit).clamp(-0.6, 0.6);
  final rGain = 1.0 + tempGain;
  final bGain = 1.0 - tempGain;

  // Tint moves along the green/magenta axis: green shifts one way, red and
  // blue shift the other, so overall luminance stays roughly put instead
  // of drifting with the color shift (unlike nudging green alone). Sign
  // matches Lightroom and this slider's own green->magenta gradient
  // (editor_screen.dart's 'Tint' _SliderSpec): positive = magenta (green
  // down, red/blue up), negative = green (green up, red/blue down).
  final tintShift = tint / 100.0 * 0.2;
  final gGain = 1.0 - tintShift;
  final rbGain = 1.0 + tintShift * 0.5;

  for (var i = 0; i < img.length; i += 3) {
    img[i] *= rGain * rbGain;
    img[i + 1] *= gGain;
    img[i + 2] *= bGain * rbGain;
  }
}

void _applyExposure(Float32List img, double exposure) {
  if (exposure == 0) {
    return;
  }
  final factor = math.pow(2.0, exposure / 100.0 * 3.0).toDouble();
  for (var i = 0; i < img.length; i++) {
    img[i] *= factor;
  }
}

void _applyBrightnessContrast(
  Float32List img,
  double brightness,
  double contrast,
) {
  if (brightness == 0 && contrast == 0) {
    return;
  }
  final contrastFactor = 1.0 + contrast / 100.0;
  for (var i = 0; i < img.length; i++) {
    img[i] = (img[i] - 127.5) * contrastFactor + 127.5 + brightness;
  }
}

void _applyHighlightsShadows(
  Float32List img,
  int pixelCount,
  double highlights,
  double shadows,
) {
  if (highlights == 0 && shadows == 0) {
    return;
  }
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    // Luminance is computed once from the input and reused for both
    // weights below, matching the Python function (it doesn't recompute
    // luminance after applying the shadows adjustment).
    final luminance = luminanceRgb(img[i], img[i + 1], img[i + 2]) / 255.0;
    if (shadows != 0) {
      final weight = (1.0 - luminance * 2.0).clamp(0.0, 1.0);
      final add = weight * (shadows / 100.0) * 80.0;
      img[i] += add;
      img[i + 1] += add;
      img[i + 2] += add;
    }
    if (highlights != 0) {
      final weight = ((luminance - 0.5) * 2.0).clamp(0.0, 1.0);
      final add = weight * (highlights / 100.0) * 80.0;
      img[i] += add;
      img[i + 1] += add;
      img[i + 2] += add;
    }
  }
}

void _applyWhitesBlacks(
  Float32List img,
  int pixelCount,
  double whites,
  double blacks,
) {
  if (whites == 0 && blacks == 0) {
    return;
  }
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final luminance = luminanceRgb(img[i], img[i + 1], img[i + 2]) / 255.0;
    if (whites != 0) {
      final weight = ((luminance - 0.75) * 4.0).clamp(0.0, 1.0);
      final add = weight * (whites / 100.0) * 100.0;
      img[i] += add;
      img[i + 1] += add;
      img[i + 2] += add;
    }
    if (blacks != 0) {
      final weight = (1.0 - luminance * 4.0).clamp(0.0, 1.0);
      final add = weight * (blacks / 100.0) * 100.0;
      img[i] += add;
      img[i + 1] += add;
      img[i + 2] += add;
    }
  }
}

void _applyVibrance(Float32List img, int pixelCount, double amount) {
  if (amount == 0) {
    return;
  }
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = img[i], g = img[i + 1], b = img[i + 2];
    final luminance = luminanceRgb(r, g, b);
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final currentSaturation = (maxC - minC) / 255.0;
    final factor = 1.0 + (amount / 100.0) * (1.0 - currentSaturation);
    img[i] = luminance + (r - luminance) * factor;
    img[i + 1] = luminance + (g - luminance) * factor;
    img[i + 2] = luminance + (b - luminance) * factor;
  }
}

void _applySaturation(Float32List img, int pixelCount, double amount) {
  if (amount == 0) {
    return;
  }
  final factor = 1.0 + amount / 100.0;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = img[i], g = img[i + 1], b = img[i + 2];
    final luminance = luminanceRgb(r, g, b);
    img[i] = luminance + (r - luminance) * factor;
    img[i + 1] = luminance + (g - luminance) * factor;
    img[i + 2] = luminance + (b - luminance) * factor;
  }
}
