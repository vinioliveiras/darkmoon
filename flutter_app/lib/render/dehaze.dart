import 'dart:math' as math;
import 'dart:typed_data';

import 'blur.dart';
import 'calibration.dart';
import 'color_space.dart';

/// Dark-channel-prior atmospheric light Solstice assumes for every photo
/// (a fixed near-white, slightly blue sky color) rather than estimating it
/// per image — see [applyDehaze]'s doc comment for why this replaced a
/// full-image dark-channel percentile search.
const double _atmR = 0.95;
const double _atmG = 0.97;
const double _atmB = 1.0;

/// Wide-radius blur Solstice's structure_blur_view uses, both for its
/// Structure local-contrast control (which Darkmoon doesn't expose — see
/// `local_contrast.dart`'s Texture/Clarity for the two it does) and,
/// separately, as Dehaze's "regional" dark-channel source below.
const double _structureBlurSigma = 40.0;

double _linearLuma(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

double _smoothstep(double edge0, double edge1, double value) {
  final t = ((value - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

double _min3(double a, double b, double c) => math.min(a, math.min(b, c));

/// A single-image haze removal / addition effect based on the dark-channel
/// prior (He, Sun & Tang) — a faithful port of Solstice's `apply_dehaze`
/// (shader.wgsl), replacing this function's previous, considerably
/// different implementation (a port of the Python app's own dehaze, which
/// estimated atmospheric light per photo from a full-image dark-channel
/// percentile search, then derived transmission from a large min-filter +
/// box-blur pair).
///
/// Solstice instead: assumes a fixed atmospheric light ([_atmR]/[_atmG]/
/// [_atmB]) rather than estimating one (cheaper, and the estimation step
/// was the one genuinely-global, GPU-unfriendly part of the old
/// algorithm); derives each pixel's transmission from *two* dark-channel
/// readings — the exact per-pixel value and a wide-radius (sigma
/// [_structureBlurSigma]) blurred/"regional" one — blended by a
/// halo-protection mask so a strong haze pull near a sharp edge doesn't
/// drag a visible glow across it (a per-pixel-only dark channel is noisy
/// there; a regional-only one bleeds across the edge); and finishes with a
/// shadow lift and a saturation boost proportional to how much haze was
/// actually removed. Operates in scene-linear light (not the gamma-encoded
/// byte buffer this pipeline otherwise stays in between stages), same as
/// the rest of Solstice's tonal pipeline.
///
/// Operates in place on a packed RGB [Float32List] (3 values/pixel, 0-255).
void applyDehaze(Float32List img, int width, int height, double amount) {
  if (amount == 0) {
    return;
  }
  final pixelCount = width * height;
  final strength = amount / 100.0;

  // The "regional" dark-channel source: blur the gamma-encoded buffer
  // (this pipeline's universal between-stage convention) at sigma 40, then
  // linearize the blurred result per pixel below — mirrors apply_dehaze's
  // own non-RAW-input branch (`srgb_to_linear(blurred_color_input_space)`),
  // since Darkmoon's byte buffer is always gamma-encoded at this point in
  // the pipeline regardless of whether the source was a RAW file.
  final rChannel = Float32List(pixelCount);
  final gChannel = Float32List(pixelCount);
  final bChannel = Float32List(pixelCount);
  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    rChannel[p] = img[i];
    gChannel[p] = img[i + 1];
    bChannel[p] = img[i + 2];
  }
  final blurredR = gaussianBlurChannel(
    rChannel,
    width,
    height,
    _structureBlurSigma,
  );
  final blurredG = gaussianBlurChannel(
    gChannel,
    width,
    height,
    _structureBlurSigma,
  );
  final blurredB = gaussianBlurChannel(
    bChannel,
    width,
    height,
    _structureBlurSigma,
  );

  for (var p = 0; p < pixelCount; p++) {
    final i = p * 3;
    final r = srgbToLinear(img[i] / 255.0);
    final g = srgbToLinear(img[i + 1] / 255.0);
    final b = srgbToLinear(img[i + 2] / 255.0);
    final br = srgbToLinear(blurredR[p] / 255.0);
    final bg = srgbToLinear(blurredG[p] / 255.0);
    final bb = srgbToLinear(blurredB[p] / 255.0);

    double outR, outG, outB;
    if (strength > 0) {
      final pixelDark = _min3(r, g, b);
      final regionalDark = _min3(br, bg, bb);
      final pixelLuma = _linearLuma(
        math.max(r, 0.0),
        math.max(g, 0.0),
        math.max(b, 0.0),
      );
      final blurredLuma = _linearLuma(
        math.max(br, 0.0),
        math.max(bg, 0.0),
        math.max(bb, 0.0),
      );
      final edgeDiff = (math.sqrt(math.max(pixelLuma, 0.0)) -
              math.sqrt(math.max(blurredLuma, 0.0)))
          .abs();
      final haloProtection = _smoothstep(0.02, 0.15, edgeDiff);
      final spatialDark =
          regionalDark + (pixelDark - regionalDark) * haloProtection;
      final safeDark = math.max(spatialDark - 0.02, 0.0);
      final mappedHaze = safeDark / (safeDark + 0.2);
      final t = math.max(
        1.0 - strength * mappedHaze * calDehazeTransmissionCoeff,
        calDehazeTransmissionFloor,
      );

      var recR = (r - _atmR) / t + _atmR;
      var recG = (g - _atmG) / t + _atmG;
      var recB = (b - _atmB) / t + _atmB;

      final recLuma = _linearLuma(
        math.max(recR, 0.0),
        math.max(recG, 0.0),
        math.max(recB, 0.0),
      );
      final shadowLift = _smoothstep(0.1, 0.0, recLuma) * (1.0 - t) * 0.15;
      recR += shadowLift;
      recG += shadowLift;
      recB += shadowLift;

      final satBoost = (1.0 - t) * calDehazeSatBoost;
      final finalLuma = _linearLuma(
        math.max(recR, 0.0),
        math.max(recG, 0.0),
        math.max(recB, 0.0),
      );
      final satFactor = 1.0 + satBoost;
      outR = math.max(finalLuma + (recR - finalLuma) * satFactor, 0.0);
      outG = math.max(finalLuma + (recG - finalLuma) * satFactor, 0.0);
      outB = math.max(finalLuma + (recB - finalLuma) * satFactor, 0.0);
    } else {
      final regionalDark = _min3(br, bg, bb);
      final safeDark = math.max(regionalDark - 0.02, 0.0);
      final mappedDepth = safeDark / (safeDark + 0.2);
      final depthFactor = 0.4 + 0.6 * mappedDepth;
      final hazeAmount = -strength;
      final mixAmount = hazeAmount * calDehazeAddMix * depthFactor;
      outR = r + (_atmR - r) * mixAmount;
      outG = g + (_atmG - g) * mixAmount;
      outB = b + (_atmB - b) * mixAmount;
    }

    img[i] = linearToSrgb(outR) * 255.0;
    img[i + 1] = linearToSrgb(outG) * 255.0;
    img[i + 2] = linearToSrgb(outB) * 255.0;
  }
}
