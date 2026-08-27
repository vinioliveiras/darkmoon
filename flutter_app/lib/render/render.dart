import 'dart:math' as math;
import 'dart:typed_data';

import 'ai_denoise.dart';
import 'baseline_chroma.dart';
import 'blur.dart';
import 'color_grading.dart';
import 'color_mixer.dart';
import 'color_space.dart';
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
const int _tonalBlurHaloPx = 18; // sigma 3.5 tonal blur, three box passes

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
  if (params.shadows != 0 || params.blacks != 0 || params.whites != 0) {
    halo += _tonalBlurHaloPx;
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

/// Every point-operation stage that runs *after* denoise, up to (but not
/// including) Sharpen/Texture/Clarity: brightness/contrast, highlights/
/// shadows, whites/blacks, tone + color curves, color mixer, color
/// grading. Split out from [applyLocalAdjustmentSteps] for the same
/// mirrored by `shaders/point_ops_post_denoise.frag` in the GPU path.
void applyPostDenoisePointOps(
  Float32List buffer,
  int width,
  int height,
  RenderParams params,
) {
  final pixelCount = width * height;
  final tonalBlur = (params.shadows == 0 &&
          params.blacks == 0 &&
          params.whites == 0)
      ? null
      : gaussianBlurChannel(
          _luminanceChannel(buffer, pixelCount),
          width,
          height,
          3.5,
        );
  _applyRapidBrightness(buffer, params.brightness);
  _applyRapidWhites(buffer, pixelCount, params.whites);
  _applyRapidHighlights(buffer, pixelCount, params.highlights);
  _applyRapidShadowsBlacks(
    buffer,
    pixelCount,
    params.shadows,
    params.blacks,
    tonalBlur,
  );
  _applyRapidContrast(buffer, params.contrast);
  applyToneCurve(buffer, params.curves.tone);
  applyColorCurves(
    buffer,
    params.curves.red,
    params.curves.green,
    params.curves.blue,
  );
  applyColorMixer(buffer, params.colorMixer);
  applyColorGrading(buffer, params.colorGrading);
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
  _applyExposure(buffer, params.exposure);
  applyDehaze(buffer, width, height, params.dehaze);
  _applyWhiteBalance(buffer, params.temperature, params.tint);
  applyPostDenoisePointOps(buffer, width, height, params);
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
  // RapidRAW represents temperature as a normalized -1..1 control with
  // multipliers (1 + temp*0.2, 1 + temp*0.05, 1 - temp*0.2). Keep
  // Darkmoon's Kelvin UI, but derive that normalized value from the existing
  // calibrated mired gain so both controls use the same color model.
  final rapidTemperature = tempGain / 0.2;
  final rTemperatureGain = 1.0 + rapidTemperature * 0.2;
  final gTemperatureGain = 1.0 + rapidTemperature * 0.05;
  final bTemperatureGain = 1.0 - rapidTemperature * 0.2;

  // Tint moves along the green/magenta axis: green shifts one way, red and
  // blue shift the other, so overall luminance stays roughly put instead
  // of drifting with the color shift (unlike nudging green alone). Sign
  // matches Lightroom and this slider's own green->magenta gradient
  // (editor_screen.dart's 'Tint' _SliderSpec): positive = magenta (green
  // down, red/blue up), negative = green (green up, red/blue down).
  final rapidTint = tint / 100.0;
  final gTintGain = 1.0 - rapidTint * 0.25;
  final rbTintGain = 1.0 + rapidTint * 0.25;
  final tintMean = (2.0 * rbTintGain + gTintGain) / 3.0;
  final tintNormalization = 1.0 / tintMean;

  for (var i = 0; i < img.length; i += 3) {
    img[i] *= rTemperatureGain * rbTintGain * tintNormalization;
    img[i + 1] *= gTemperatureGain * gTintGain * tintNormalization;
    img[i + 2] *= bTemperatureGain * rbTintGain * tintNormalization;
  }
}

void _applyExposure(Float32List img, double exposure) {
  if (exposure == 0) {
    return;
  }
  final factor = math.pow(2.0, exposure / 20.0).toDouble();
  for (var i = 0; i < img.length; i++) {
    img[i] *= factor;
  }
}

/// EXPERIMENTAL (not yet validated against a wide range of presets —
/// flagged here deliberately): Contrast used to be a pure linear scale
/// toward 127.5 (`(x-127.5)*factor+127.5`), which has no floor on how far
/// it can crush blacks up or pull whites down — Contrast=-40 alone lifted
/// black to 51 and pulled white to 204, *before* Shadows/Whites/Blacks
/// even ran, compounding into a visibly washed/hazy look on presets that
/// lean on several Basic sliders at once (e.g. a real preset combining
/// Contrast=-40, Shadows=+100, Whites=+58). Replaced with an
/// endpoint-preserving S-curve (0 always maps to 0, 255 always maps to
/// 255, regardless of strength) — same curve shape used for RapidRAW's
/// (a sibling project) shader contrast: gamma > 1 steepens the curve
/// (more contrast), gamma < 1 flattens it (less contrast) while the true
/// black/white points never move.
void _applyRapidBrightness(Float32List img, double brightness) {
  if (brightness == 0) {
    return;
  }
  final adjustment = brightness / 20.0;
  const rationalCurveMix = 0.95;
  const midtoneStrength = 1.2;
  const topAnchor = 1.06;
  for (var i = 0; i < img.length; i += 3) {
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final originalLuma =
      _linearLuminance(r, g, b);
    if (originalLuma.abs() < 0.00001) {
      continue;
    }
    final directAdjustment = adjustment * (1 - rationalCurveMix);
    final rationalAdjustment = adjustment * rationalCurveMix;
    final scale = math.pow(2.0, directAdjustment).toDouble();
    final k = math.pow(2.0, -rationalAdjustment * midtoneStrength).toDouble();
    final lumaFloor = (originalLuma.abs() / topAnchor).floor() * topAnchor;
    final lumaNorm = (originalLuma.abs() - lumaFloor) / topAnchor;
    final shapedNorm = lumaNorm / (lumaNorm + (1 - lumaNorm) * k);
    final shapedLuma = lumaFloor + shapedNorm * topAnchor;
    final newLuma = shapedLuma * scale;
    final totalLumaScale = newLuma / originalLuma;
    final lumaWeight = (newLuma.clamp(0.0, 2.0)) * 0.5;
    final dynamicExponent = 0.95 + (0.65 - 0.95) * lumaWeight;
    final chromaScale = math.pow(totalLumaScale, dynamicExponent).toDouble() /
        (1 + math.max(0.0, newLuma - 0.9) * 2.0);
    img[i] = linearToSrgb(newLuma + (r - originalLuma) * chromaScale) * 255.0;
    img[i + 1] =
      linearToSrgb(newLuma + (g - originalLuma) * chromaScale) * 255.0;
    img[i + 2] =
      linearToSrgb(newLuma + (b - originalLuma) * chromaScale) * 255.0;
  }
}

void _applyRapidContrast(Float32List img, double contrast) {
  if (contrast == 0) {
    return;
  }
  final gamma = math.pow(2.0, contrast / 100.0 * 1.25).toDouble();
  for (var i = 0; i < img.length; i++) {
    final linear = srgbToLinear(img[i] / 255.0);
    final perceptual = math.pow(linear, 1.0 / 2.2).toDouble();
    final curved = perceptual < 0.5
        ? 0.5 * math.pow(2.0 * perceptual, gamma)
        : 1.0 - 0.5 * math.pow(2.0 * (1.0 - perceptual), gamma);
    img[i] = linearToSrgb(
          math.pow(curved.clamp(0.0, 1.0), 2.2).toDouble(),
        ) *
        255.0;
  }
}

void _applyRapidWhites(
  Float32List img,
  int pixelCount,
  double whites,
) {
  if (whites == 0) return;
  final amount = whites / 100.0;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final luma = _linearLuminance(r, g, b);
    final x = math.max(luma, 0.0001) * 1.5;
    final whiteMaskInput = (math.exp(2.0 * x) - 1.0) /
      (math.exp(2.0 * x) + 1.0);
    final whiteT = ((whiteMaskInput - 0.5) / (0.98 - 0.5)).clamp(0.0, 1.0);
    final whiteMask = whiteT * whiteT * (3.0 - 2.0 * whiteT);
    final multiplier = 1.0 / math.max(1.0 - amount * 0.25 * whiteMask, 0.01);
    img[i] = linearToSrgb(r * multiplier) * 255.0;
    img[i + 1] = linearToSrgb(g * multiplier) * 255.0;
    img[i + 2] = linearToSrgb(b * multiplier) * 255.0;
  }
}

void _applyRapidShadowsBlacks(
  Float32List img,
  int pixelCount,
  double shadows,
  double blacks,
  Float32List? tonalBlur,
) {
  if (shadows == 0 && blacks == 0) return;
  final shadowAmount = shadows / 100.0;
  final blackAmount = blacks / 100.0;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final luma = _linearLuminance(r, g, b);
    final t = math.pow(math.max(luma, 0.0001), 0.4545).toDouble();
    final shadowLift = shadowAmount * t * math.pow(math.max(1.0 - t, 0.0), 4.5);
    final blackLift = blackAmount * t * math.pow(math.max(1.0 - t, 0.0), 12.0);
    final lift = math.max(shadowLift + blackLift, 0.0);
    final curved = math.max(t + shadowLift + blackLift, 0.0);
    final stretch = 1.0 + lift * 1.3;
    final contrasted = 0.2 + (curved - 0.2) * stretch;
    final finalT = math.max(curved * 0.15 + contrasted * 0.85, 0.0);
    final newLuma = math.pow(finalT, 2.2).toDouble();
    final ratio = newLuma / math.max(luma, 0.0001);
    final blurredLuma = tonalBlur == null ? luma : tonalBlur[p];
    final blurredT = math.pow(math.max(blurredLuma, 0.0001), 0.4545).toDouble();
    final detailRatio = (t / math.max(blurredT, 0.0001)).clamp(0.8, 1.25);
    final noiseProtection = (blurredT / 0.1).clamp(0.0, 1.0);
    final detailExponent = 1.0 + lift * 1.2 * noiseProtection;
    final detailCorrection =
      math.pow(detailRatio, detailExponent).toDouble() / detailRatio;
    final multiplier = ratio * math.pow(detailCorrection, 2.2).toDouble();
    img[i] = linearToSrgb(r * multiplier) * 255.0;
    img[i + 1] = linearToSrgb(g * multiplier) * 255.0;
    img[i + 2] = linearToSrgb(b * multiplier) * 255.0;
  }
}

Float32List _luminanceChannel(Float32List rgb, int pixelCount) {
  final channel = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    channel[p] = _linearLuminance(
      srgbToLinear(rgb[i] / 255.0),
      srgbToLinear(rgb[i + 1] / 255.0),
      srgbToLinear(rgb[i + 2] / 255.0),
    );
  }
  return channel;
}

double _tanh(double value) {
  final e = math.exp(2.0 * value);
  return (e - 1.0) / (e + 1.0);
}

double _linearLuminance(double r, double g, double b) =>
  0.2126 * r + 0.7152 * g + 0.0722 * b;

void _applyRapidHighlights(Float32List img, int pixelCount, double highlights) {
  if (highlights == 0) return;
  final amount = highlights / 100.0;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final luma = _linearLuminance(r, g, b);
    final maskInput = _tanh(luma * 1.5);
    final t = ((maskInput - 0.55) / (0.95 - 0.55)).clamp(0.0, 1.0);
    final mask = t * t * (3.0 - 2.0 * t);
    if (mask == 0) continue;
    final newLuma = amount < 0
        ? math.pow(luma, 1.0 - amount * 1.75).toDouble()
        : luma * math.pow(2.0, amount * 1.75).toDouble();
    final ratio = newLuma / math.max(luma, 0.0001);
    final multiplier = 1.0 + (ratio - 1.0) * mask;
    img[i] = linearToSrgb(r * multiplier) * 255.0;
    img[i + 1] = linearToSrgb(g * multiplier) * 255.0;
    img[i + 2] = linearToSrgb(b * multiplier) * 255.0;
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
    if (maxC - minC < 0.02 * 255.0) {
      continue;
    }
    final safeMax = math.max(maxC, 0.001);
    final currentSaturation = (maxC - minC) / safeMax;
    final hsv = _rgbToHsv(r / 255.0, g / 255.0, b / 255.0);
    final hueDistance = math.min(
      (hsv[0] - 25.0).abs(),
      360.0 - (hsv[0] - 25.0).abs(),
    );
    final skin = _smoothstep(35.0, 10.0, hueDistance);
    final skinDampener = 1.0 + (0.6 - 1.0) * skin;
    final normalizedAmount = amount / 100.0;
    final factor = normalizedAmount >= 0
      ? 1.0 + normalizedAmount *
        (1.0 - _smoothstep(0.4, 0.9, currentSaturation)) *
        skinDampener *
        3.0
      : 1.0 + normalizedAmount *
        (1.0 - _smoothstep(0.2, 0.8, currentSaturation));
    img[i] = luminance + (r - luminance) * factor;
    img[i + 1] = luminance + (g - luminance) * factor;
    img[i + 2] = luminance + (b - luminance) * factor;
  }
}

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

List<double> _rgbToHsv(double r, double g, double b) {
  final maxC = math.max(r, math.max(g, b));
  final minC = math.min(r, math.min(g, b));
  final delta = maxC - minC;
  var hue = 0.0;
  if (delta > 0) {
    if (maxC == r) {
      hue = 60.0 * ((g - b) / delta % 6.0);
    } else if (maxC == g) {
      hue = 60.0 * ((b - r) / delta + 2.0);
    } else {
      hue = 60.0 * ((r - g) / delta + 4.0);
    }
    if (hue < 0) hue += 360.0;
  }
  return [hue, maxC == 0 ? 0.0 : delta / maxC, maxC];
}

/// How strongly a pixel ([r], [g], [b], each 0..1) reads as a skin tone
/// (0..1) — Lightroom's Vibrance (unlike a plain Saturation slider) damps
/// its own effect on skin-tone hues so faces don't oversaturate. Centered
/// on the Color Mixer's Orange band (30°, see `_channelCenterHues` in
/// color_mixer.dart), with a narrower half-width since skin tones occupy a
/// tighter hue range than a full Orange mixer band.
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
