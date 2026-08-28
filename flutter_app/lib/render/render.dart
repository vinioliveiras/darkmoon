import 'dart:math' as math;
import 'dart:typed_data';

import 'ai_denoise.dart';
import 'baseline_chroma.dart';
import 'blur.dart';
import 'calibration.dart';
import 'color_grading.dart';
import 'color_mixer.dart';
import 'color_space.dart';
import 'dehaze.dart';
import 'grain.dart';
import 'hsl.dart';
import 'local_contrast.dart';
import 'mask.dart';
import 'render_params.dart';
import 'sharpen.dart';
import 'tone_curve.dart';
import 'vignette.dart';
import 'white_balance.dart';


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
      RenderParams.fromValues(
        mask.values,
        curves: mask.curves,
        asShotKelvin: globalParams.asShotKelvin,
        asShotTint: globalParams.asShotTint,
      ),
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
const int _tonalBlurHaloPx = 18; // sigma 3.5 tonal blur, three box passes

/// Blur reach (px) for a given Gaussian sigma plus the 6px local-variance
/// window Texture/Clarity layer on top — derived from `calTextureSigma` /
/// `calClaritySigma` so bumping those in `calibration.dart` keeps the
/// parallel-render band padding correct (no seams). Rounds up generously:
/// at the shipping sigmas (3 / 25) this yields 29 / 128, safely above the
/// hand-measured 30 / 110 the fixed sigmas used before.
int _localContrastHaloPx(double sigma) => (sigma * 4.5).ceil() + 15;

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
    halo += _localContrastHaloPx(calTextureSigma);
  }
  if (params.clarity != 0) {
    halo += _localContrastHaloPx(calClaritySigma);
  }
  if (params.shadows != 0 || params.blacks != 0 || params.whites != 0) {
    halo += _tonalBlurHaloPx;
  }
  return halo;
}

/// Halo (px) [applyExposureAndDehaze] needs when run on a horizontal band
/// — the reach of Dehaze's sigma-40 "structure" Gaussian (3-pass box,
/// ~4.5·sigma), 0 when Dehaze is off (then it's just the O(n) exposure
/// multiply).
int exposureDehazeHaloPx(RenderParams params) =>
    params.dehaze != 0 ? 180 : 0;

/// Halo (px) [applyGlobalPointOps] needs on a band — just the sigma-3.5
/// tonal blur behind Shadows/Whites/Blacks.
int globalPointOpsHaloPx(RenderParams params) =>
    (params.shadows != 0 || params.blacks != 0 || params.whites != 0)
    ? 24
    : 0;

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
    params.texture * calTextureStrength,
    calTextureSigma,
    noiseAware: true,
  );
  applyLocalContrast(
    buffer,
    width,
    height,
    params.clarity * calClarityStrength,
    calClaritySigma,
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
  // Lightroom's parametric Tone Curve runs into the same result as the
  // point curve; apply it first, then the point curve on top.
  if (!params.parametricCurve.isIdentity) {
    applyToneCurve(buffer, parametricCurvePoints(params.parametricCurve));
  }
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

/// Everything [applyLocalAdjustmentSteps] leaves out. Split into two:
///
/// - [applyExposureAndDehaze] — Exposure (a plain scale) then Dehaze
///   (`dehaze.dart`), whose wide "regional" blur means it can't be run on
///   a naive per-band slice; kept whole-image.
/// - [applyGlobalPointOps] — White Balance, the post-denoise point ops
///   (brightness/contrast/highlights/shadows/whites/blacks, tone + colour
///   curves, mixer, grading), Saturation, Vibrance, Vignette, Grain. All
///   per-pixel with no blur, so `render_parallel.dart` runs this half in
///   bands too — it's where most of the `pow()` cost of a full-resolution
///   render lives.
void applyGlobalAdjustmentSteps(
  Float32List buffer,
  int width,
  int height,
  RenderParams params,
) {
  applyExposureAndDehaze(buffer, width, height, params);
  applyGlobalPointOps(buffer, width, height, params);
}

void applyExposureAndDehaze(
  Float32List buffer,
  int width,
  int height,
  RenderParams params,
) {
  _applyExposure(buffer, params.exposure);
  applyDehaze(buffer, width, height, params.dehaze);
}

/// [rowOffset]/[fullHeight]: when [buffer] is one horizontal band of a
/// larger image, its row 0's absolute index and the full frame height —
/// so Vignette (radial from the frame centre) and Grain (frame-anchored
/// noise) stitch back seamlessly. Every other step here is a pure
/// per-pixel op and ignores them.
void applyGlobalPointOps(
  Float32List buffer,
  int width,
  int height,
  RenderParams params, {
  int rowOffset = 0,
  int? fullHeight,
}) {
  final pixelCount = width * height;
  _applyWhiteBalance(
    buffer,
    params.temperature,
    params.tint,
    params.asShotKelvin,
    params.asShotTint,
    params.preserveTintBrightness,
  );
  applyPostDenoisePointOps(buffer, width, height, params);
  // Saturation before Vibrance, matching RapidRAW's apply_creative_color:
  // Vibrance's saturation/hue masks read the already-saturated color.
  _applySaturation(buffer, pixelCount, params.saturation);
  _applyVibrance(buffer, pixelCount, params.vibrance);
  applyVignette(
    buffer,
    width,
    height,
    params.vignette,
    rowOffset: rowOffset,
    fullHeight: fullHeight,
  );
  // Grain is the last thing RapidRAW's shader adds, after curves and
  // vignette — a texture layered on the finished image, not something the
  // later stages should react to.
  applyGrain(
    buffer,
    width,
    height,
    params.grain,
    rowOffset: rowOffset,
    fullHeight: fullHeight,
  );
}

Uint8List _toUint8(Float32List buffer) {
  final out = Uint8List(buffer.length);
  for (var i = 0; i < buffer.length; i++) {
    out[i] = buffer[i].clamp(0.0, 255.0).round();
  }
  return out;
}

/// White balance: a Von Kries per-channel gain (see [whiteBalanceGains])
/// mapping the target illuminant's reference white onto the photo's
/// already-neutral as-shot white. At `temperature == asShotKelvin &&
/// tint == asShotTint` it's a no-op — the LibRaw decode already applied
/// the camera's white balance.
///
/// [preserveTintBrightness] is retained for the (unchanged) call
/// signature and the settings toggle, but the model is luminance-
/// normalised by construction now, so it no longer changes anything.
void _applyWhiteBalance(
  Float32List img,
  double temperatureKelvin,
  double tint,
  double asShotKelvin,
  double asShotTint,
  bool preserveTintBrightness,
) {
  if (temperatureKelvin == asShotKelvin && tint == asShotTint) {
    return;
  }
  final gains = whiteBalanceGains(
    temperatureKelvin,
    tint,
    asShotKelvin,
    asShotTint,
  );
  for (var i = 0; i < img.length; i += 3) {
    img[i] *= gains.r;
    img[i + 1] *= gains.g;
    img[i + 2] *= gains.b;
  }
}

void _applyExposure(Float32List img, double exposure) {
  if (exposure == 0) {
    return;
  }
  final factor = math.pow(2.0, exposure / calExposureUnitsPerStop).toDouble();
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
  final adjustment = brightness / calBrightnessUnitsPerStop;
  const rationalCurveMix = 0.95;
  const midtoneStrength = calBrightnessMidtoneStrength;
  const topAnchor = 1.06;
  // Loop-invariant — these depend only on `brightness`, not the pixel.
  final directAdjustment = adjustment * (1 - rationalCurveMix);
  final rationalAdjustment = adjustment * rationalCurveMix;
  final scale = math.pow(2.0, directAdjustment).toDouble();
  final k = math.pow(2.0, -rationalAdjustment * midtoneStrength).toDouble();
  for (var i = 0; i < img.length; i += 3) {
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final originalLuma =
      _linearLuminance(r, g, b);
    if (originalLuma.abs() < 0.00001) {
      continue;
    }
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
  // Contrast is a pure byte-in -> byte-out S-curve with a per-render gamma,
  // so bake it into a 257-entry LUT once and interpolate — the pixel loop
  // then costs a lookup instead of ~4 pow() per channel.
  final gamma =
      math.pow(2.0, contrast / 100.0 * calContrastStrength).toDouble();
  final lut = Float32List(257);
  for (var v = 0; v <= 256; v++) {
    final perceptual = perceptualEncode(srgbToLinear(v / 256.0));
    final curved = perceptual < 0.5
        ? 0.5 * math.pow(2.0 * perceptual, gamma).toDouble()
        : 1.0 - 0.5 * math.pow(2.0 * (1.0 - perceptual), gamma).toDouble();
    lut[v] = linearToSrgb(perceptualDecode(curved.clamp(0.0, 1.0))) * 255.0;
  }
  for (var i = 0; i < img.length; i++) {
    final x = img[i];
    final c = x <= 0.0 ? 0.0 : (x >= 255.0 ? 255.0 : x);
    final p = c * (256.0 / 255.0);
    final lo = p.toInt();
    img[i] = lo >= 256 ? lut[256] : lut[lo] + (lut[lo + 1] - lut[lo]) * (p - lo);
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
    final whiteT =
        ((whiteMaskInput - calWhitesMaskLow) / (0.98 - calWhitesMaskLow))
            .clamp(0.0, 1.0);
    final whiteMask = whiteT * whiteT * (3.0 - 2.0 * whiteT);
    final multiplier =
        1.0 / math.max(1.0 - amount * calWhitesLevelCoeff * whiteMask, 0.01);
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
  final shadowAmount = shadows / 100.0 * calShadowsAmountScale;
  final blackAmount = blacks / 100.0 * calBlacksAmountScale;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final luma = _linearLuminance(r, g, b);
    final t = perceptualEncode(math.max(luma, 0.0001));
    final oneMinusT = math.max(1.0 - t, 0.0);
    final shadowLift =
        shadowAmount * t * _powFalloff(oneMinusT, calShadowsFalloff);
    final blackLift =
        blackAmount * t * _powFalloff(oneMinusT, calBlacksFalloff);
    final lift = math.max(shadowLift + blackLift, 0.0);
    final curved = math.max(t + shadowLift + blackLift, 0.0);
    final stretch = 1.0 + lift * calShadowBlacksStretch;
    final contrasted = 0.2 + (curved - 0.2) * stretch;
    final finalT = math.max(
      curved * (1.0 - calShadowBlacksContrastMix) +
          contrasted * calShadowBlacksContrastMix,
      0.0,
    );
    // finalT / detailCorrection can legitimately exceed 1 (overshoot on
    // lifted pixels) so they keep the real pow — clamping to the LUT's
    // [0, 1] would cap a genuine boost.
    final newLuma = math.pow(finalT, 2.2).toDouble();
    final ratio = newLuma / math.max(luma, 0.0001);
    final blurredLuma = tonalBlur == null ? luma : tonalBlur[p];
    final blurredT = perceptualEncode(math.max(blurredLuma, 0.0001));
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

/// `pow(x, exp)` for the two fixed Shadows/Blacks falloff exponents,
/// computed by multiplication (× ~15 faster than `math.pow` with a
/// fractional exponent, and exact). Falls back to `pow` for any other
/// value (`calShadowsFalloff` / `calBlacksFalloff` retuned).
double _powFalloff(double x, double exp) {
  if (exp == 4.5) {
    final x2 = x * x;
    return x2 * x2 * math.sqrt(x);
  }
  if (exp == 9.0) {
    final x3 = x * x * x;
    return x3 * x3 * x3;
  }
  return math.pow(x, exp).toDouble();
}

void _applyRapidHighlights(Float32List img, int pixelCount, double highlights) {
  if (highlights == 0) return;
  final amount = highlights / 100.0;
  // Loop-invariant for the positive branch.
  final gainPos = math.pow(2.0, amount * calHighlightsStrength).toDouble();
  final expNeg = 1.0 - amount * calHighlightsStrength;
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
        ? math.pow(luma, expNeg).toDouble()
        : luma * gainPos;
    final ratio = newLuma / math.max(luma, 0.0001);
    final multiplier = 1.0 + (ratio - 1.0) * mask;
    img[i] = linearToSrgb(r * multiplier) * 255.0;
    img[i + 1] = linearToSrgb(g * multiplier) * 255.0;
    img[i + 2] = linearToSrgb(b * multiplier) * 255.0;
  }
}

/// How strongly a pixel ([r], [g], [b], each 0..1) reads as a skin tone
/// (0..1) — Lightroom's Vibrance (unlike a plain Saturation slider) damps
/// its own effect on skin-tone hues so faces don't oversaturate. Centered
/// on the same 25° hue RapidRAW's own Color Mixer/HSL panel centers its
/// Orange band on (see `_hslRanges` in color_mixer.dart), with a narrower
/// half-width since skin tones occupy a tighter hue range than a full
/// Orange mixer band.
///
/// RapidRAW's `apply_creative_color` does this math on scene-linear RGB
/// (its whole pipeline stays linear until final display encode), so both
/// the luminance mix and the saturation/hue readings driving the masks
/// below must run on linear values too — computing them on gamma-encoded
/// bytes (as this used to) systematically under-masks shadows and
/// over-masks highlights relative to RapidRAW, since sRGB's gamma curve
/// compresses the same linear-light saturation differently at each end.
void _applyVibrance(Float32List img, int pixelCount, double amount) {
  if (amount == 0) {
    return;
  }
  final normalizedAmount = amount / 100.0;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final luminance = _linearLuminance(r, g, b);
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    if (maxC - minC < 0.02) {
      continue;
    }
    final currentSaturation = (maxC - minC) / math.max(maxC, 0.001);
    final hsv = rgbToHsv(r, g, b);
    final hueDistance = math.min(
      (hsv[0] - 25.0).abs(),
      360.0 - (hsv[0] - 25.0).abs(),
    );
    final skin = _smoothstep(35.0, 10.0, hueDistance);
    final skinDampener = 1.0 + (calVibranceSkinDampen - 1.0) * skin;
    final factor = normalizedAmount >= 0
      ? 1.0 + normalizedAmount *
        (1.0 - _smoothstep(0.4, 0.9, currentSaturation)) *
        skinDampener *
        calVibranceStrength
      : 1.0 + normalizedAmount *
        (1.0 - _smoothstep(0.2, 0.8, currentSaturation));
    img[i] = linearToSrgb(luminance + (r - luminance) * factor) * 255.0;
    img[i + 1] = linearToSrgb(luminance + (g - luminance) * factor) * 255.0;
    img[i + 2] = linearToSrgb(luminance + (b - luminance) * factor) * 255.0;
  }
}

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// Flat saturation gain, same linear-light mix as [_applyVibrance] but
/// without any saturation/hue-dependent masking — matches RapidRAW's
/// `apply_creative_color`, which runs this step first (see the call order
/// in [applyGlobalAdjustmentSteps]) so Vibrance's masks read the
/// already-saturated color, not the original.
void _applySaturation(Float32List img, int pixelCount, double amount) {
  if (amount == 0) {
    return;
  }
  final factor = 1.0 + amount / 100.0 * calSaturationStrength;
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final luminance = _linearLuminance(r, g, b);
    img[i] = linearToSrgb(luminance + (r - luminance) * factor) * 255.0;
    img[i + 1] = linearToSrgb(luminance + (g - luminance) * factor) * 255.0;
    img[i + 2] = linearToSrgb(luminance + (b - luminance) * factor) * 255.0;
  }
}
