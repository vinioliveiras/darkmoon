#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of the rest of applyLocalAdjustmentSteps's point-operation
// stages (everything after baseline chroma smoothing/AI denoise, up to
// but not including Sharpen/Texture/Clarity — those are Group B, Phase
// 2+): brightness/contrast, highlights/shadows, whites/blacks, tone +
// color curves, color mixer, color grading. Working space is 0..1
// throughout; every additive constant from render.dart's 0..255-space
// math is divided by 255 here to match.

uniform vec2 uSize;

// Brightness/contrast — render.dart's _applyBrightnessContrast. Contrast
// is an endpoint-preserving S-curve (0->0, 255->255 always), not a plain
// linear scale toward mid-gray — see that function's doc comment for why.
uniform float uBrightness255; // brightness param normalized from -100..100
uniform float uContrastGamma; // pow(2, contrast/100*1.25), 1.0 = no-op

// The fixed "profile" contrast curve every photo gets before the tone
// sliders — darkmoon's stand-in for the S-curve the Adobe Color profile
// bakes into Lightroom's zero-edit render (render.dart's _applyBaseContrast
// / calBaseContrast). Same endpoint-preserving S as uContrastGamma, so
// 1.0 = no-op. Applied first thing in main(), matching the CPU order
// (top of applyPostDenoisePointOps).
uniform float uBaseContrastGamma; // pow(2, baseContrast/100*1.25), 1.0 = no-op

// Highlights/shadows — _applyHighlightsShadows. Precomputed as
// (param/100)*80/255 on the CPU side so the shader just multiplies by a
// per-pixel weight.
uniform float uShadowsAdd; // shadows param normalized from -100..100
uniform float uHighlightsAdd;

// Whites/blacks — _applyWhitesBlacks. Precomputed as (param/100)*100/255.
uniform float uWhitesAdd; // whites param normalized from -100..100
uniform float uBlacksAdd; // blacks param normalized from -100..100

// Color Mixer calibration — must match lib/render/calibration.dart's
// calMixerHueStrength / calMixerBandSharpness (the CPU path reads them
// from there; this shader gets them as uniforms).
uniform float uMixerHueStrength; // degrees of hue rotation per slider unit
uniform float uMixerBandSharpness; // Gaussian tightness of each HSL band

// Color Mixer — color_mixer.dart's applyColorMixer. 8 bands x
// [hueShift, satShift, lumShift], band order matches
// ColorMixerValues._channels (red, orange, yellow, green, aqua, blue,
// purple, magenta).
uniform float uMixer[24];

// Color Grading — color_grading.dart's applyColorGrading. Tint offsets
// and luminance offsets precomputed on CPU (including the /255 scale and
// the _tintOffset's hslToRgb call, which stays on CPU since it's a
// per-range constant, not a per-pixel operation).
uniform float uGradeShadowTint[3];
uniform float uGradeMidTint[3];
uniform float uGradeHighlightTint[3];
uniform float uGradeGlobalTint[3];
uniform float uGradeShadowLum;
uniform float uGradeMidLum;
uniform float uGradeHighlightLum;
uniform float uGradeGlobalLum;

uniform sampler2D uTexture;
// 256x1 RGBA LUT: r = tone curve, g/b/a = red/green/blue color curves —
// each channel built by tone_curve.dart's buildToneCurveLut, 0..1 in and
// out (matches this shader's working space directly).
uniform sampler2D uLut;
// Tonal blur (sigma 3.5) used by RapidRAW to preserve local detail while
// lifting shadows/blacks. It is bound to the source when the controls are
// neutral so the sampler is always valid without a branch in Dart.
uniform sampler2D uTonalBlur;

out vec4 fragColor;

float srgbToLinear(float value) {
  float c = clamp(value, 0.0, 1.0);
  if (c <= 0.04045) return c / 12.92;
  return pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float value) {
  float c = clamp(value, 0.0, 1.0);
  if (c <= 0.0031308) return c * 12.92;
  return 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

// Skia's runtime-effect SkSL compiler rejects `const T arr[n] = T[](...)`
// (array initializers) — matches color_mixer.dart's _hslRanges via an
// if-chain instead of an array literal. Exact values RapidRAW's own
// HSL_RANGES uses in shader.wgsl (not evenly spaced, not a fixed width).
float hslRangeCenter(int band) {
  if (band == 0) return 358.0;
  if (band == 1) return 25.0;
  if (band == 2) return 60.0;
  if (band == 3) return 115.0;
  if (band == 4) return 180.0;
  if (band == 5) return 225.0;
  if (band == 6) return 280.0;
  return 330.0; // band == 7
}

float hslRangeWidth(int band) {
  if (band == 0) return 35.0;
  if (band == 1) return 45.0;
  if (band == 2) return 40.0;
  if (band == 3) return 90.0;
  if (band == 4) return 60.0;
  if (band == 5) return 60.0;
  if (band == 6) return 55.0;
  return 50.0; // band == 7
}

// Mirrors color_mixer.dart's _rawHslInfluence exactly (RapidRAW's
// get_raw_hsl_influence): a Gaussian falloff around center rather than a
// hard cutoff.
float rawHslInfluence(float hue, float center, float width) {
  float dist = abs(hue - center);
  if (dist > 180.0) dist = 360.0 - dist;
  float falloff = dist / (width * 0.5);
  return exp(-uMixerBandSharpness * falloff * falloff);
}

// Mirrors hsl.dart's rgbToHsv (h in degrees, s/v in 0..1) — HSV, not HSL:
// value is the max channel, not (max+min)/2.
vec3 rgbToHsv(vec3 c) {
  float maxC = max(c.r, max(c.g, c.b));
  float minC = min(c.r, min(c.g, c.b));
  float delta = maxC - minC;
  float hue = 0.0;
  if (delta > 0.0) {
    if (maxC == c.r) {
      hue = 60.0 * mod((c.g - c.b) / delta, 6.0);
    } else if (maxC == c.g) {
      hue = 60.0 * ((c.b - c.r) / delta + 2.0);
    } else {
      hue = 60.0 * ((c.r - c.g) / delta + 4.0);
    }
    if (hue < 0.0) hue += 360.0;
  }
  return vec3(hue, maxC == 0.0 ? 0.0 : delta / maxC, maxC);
}

// Mirrors hsl.dart's hsvToRgb.
vec3 hsvToRgb(float h, float s, float v) {
  float cc = v * s;
  float x = cc * (1.0 - abs(mod(h / 60.0, 2.0) - 1.0));
  float m = v - cc;
  vec3 rgbPrime;
  if (h < 60.0) { rgbPrime = vec3(cc, x, 0.0); }
  else if (h < 120.0) { rgbPrime = vec3(x, cc, 0.0); }
  else if (h < 180.0) { rgbPrime = vec3(0.0, cc, x); }
  else if (h < 240.0) { rgbPrime = vec3(0.0, x, cc); }
  else if (h < 300.0) { rgbPrime = vec3(x, 0.0, cc); }
  else { rgbPrime = vec3(cc, 0.0, x); }
  return rgbPrime + vec3(m, m, m);
}

// Endpoint-preserving S-curve (0->0, 1->1 always, regardless of gamma) —
// mirrors render.dart's _applyBrightnessContrast per-channel exactly.
// gamma==1.0 (uContrastGamma's no-contrast value) reduces to the identity
// algebraically, so this needs no separate off/no-op branch.
float contrastCurve(float t, float gamma) {
  float x = clamp(t, 0.0, 1.0);
  if (x < 0.5) {
    return 0.5 * pow(2.0 * x, gamma);
  }
  return 1.0 - 0.5 * pow(2.0 * (1.0 - x), gamma);
}

vec3 rapidBrightness(vec3 color, float amount) {
  if (amount == 0.0) return color;
  color = vec3(
    srgbToLinear(color.r),
    srgbToLinear(color.g),
    srgbToLinear(color.b)
  );
  const float rationalMix = 0.95;
  const float midtoneStrength = 1.2;
  const float topAnchor = 1.06;
  float originalLuma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  if (abs(originalLuma) < 0.00001) return color;
  float direct = amount * (1.0 - rationalMix);
  float rational = amount * rationalMix;
  float scale = pow(2.0, direct);
  float k = pow(2.0, -rational * midtoneStrength);
  float floorValue = floor(abs(originalLuma) / topAnchor) * topAnchor;
  float normalized = (abs(originalLuma) - floorValue) / topAnchor;
  float shaped = normalized / (normalized + (1.0 - normalized) * k);
  float newLuma = (floorValue + shaped * topAnchor) * scale;
  float lumaScale = newLuma / originalLuma;
  float lumaWeight = clamp(newLuma, 0.0, 2.0) * 0.5;
  float dynamicExponent = mix(0.95, 0.65, lumaWeight);
  float chromaScale = pow(lumaScale, dynamicExponent) /
      (1.0 + max(0.0, newLuma - 0.9) * 2.0);
  vec3 result = vec3(newLuma) + (color - vec3(originalLuma)) * chromaScale;
  return vec3(
    linearToSrgb(result.r),
    linearToSrgb(result.g),
    linearToSrgb(result.b)
  );
}

// Lightroom-feel calibration (item 7) — these literals must match
// lib/render/calibration.dart's calWhitesMaskLow / calWhitesLevelCoeff /
// calBlacksAmountScale / calBlacksFalloff. The CPU path reads them from
// that file; this shader (GPU render, opt-in) has them inline, so if you
// tune calibration.dart and use the GPU path, change them here too.
float rapidWhiteMask(float luma) {
  float whiteInput = tanh(max(luma, 0.0001) * 1.5);
  return smoothstep(0.32, 0.98, whiteInput);
}

vec3 rapidHighlights(vec3 color, float amount) {
  if (amount == 0.0) return color;
  vec3 linearColor = vec3(
    srgbToLinear(color.r), srgbToLinear(color.g), srgbToLinear(color.b)
  );
  float luma = dot(linearColor, vec3(0.2126, 0.7152, 0.0722));
  float mask = smoothstep(0.55, 0.95, tanh(max(luma, 0.0001) * 1.5));
  if (mask <= 0.0) return color;
  float newLuma = amount < 0.0
      ? pow(luma, 1.0 - amount * 1.75)
      : luma * pow(2.0, amount * 1.75);
  linearColor *= 1.0 + (newLuma / max(luma, 0.0001) - 1.0) * mask;
  return vec3(
    linearToSrgb(linearColor.r), linearToSrgb(linearColor.g),
    linearToSrgb(linearColor.b)
  );
}

vec3 rapidWhites(vec3 color, float amount) {
  if (amount == 0.0) return color;
  vec3 linearColor = vec3(
    srgbToLinear(color.r), srgbToLinear(color.g), srgbToLinear(color.b)
  );
  float luma = dot(max(linearColor, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));
  float mask = rapidWhiteMask(luma);
  float level = 1.0 - amount * 0.42;
  float multiplier = 1.0 / max(mix(1.0, level, mask), 0.01);
  linearColor *= multiplier;
  return vec3(
    linearToSrgb(linearColor.r), linearToSrgb(linearColor.g),
    linearToSrgb(linearColor.b)
  );
}

vec3 rapidShadowsBlacks(
  vec3 color,
  float shadows,
  float blacks,
  float blurredLuma
) {
  if (shadows == 0.0 && blacks == 0.0) return color;
  vec3 linearColor = vec3(
    srgbToLinear(color.r), srgbToLinear(color.g), srgbToLinear(color.b)
  );
  float luma = dot(max(linearColor, vec3(0.0)), vec3(0.2126, 0.7152, 0.0722));
  float t = pow(max(luma, 0.0001), 0.4545);
  float shadowLift = shadows * t * pow(max(1.0 - t, 0.0), 4.5);
  float blackLift = blacks * 1.5 * t * pow(max(1.0 - t, 0.0), 9.0);
  float lift = max(shadowLift + blackLift, 0.0);
  float curved = max(t + shadowLift + blackLift, 0.0);
  float contrasted = 0.2 + (curved - 0.2) * (1.0 + lift * 1.3);
  float finalT = max(mix(curved, contrasted, 0.85), 0.0);
  float newLuma = pow(finalT, 2.2);
  float lumaRatio = newLuma / max(luma, 0.0001);
  float detail = clamp(t / max(pow(max(blurredLuma, 0.0001), 0.4545), 0.0001), 0.8, 1.25);
  float noiseProtection = smoothstep(0.0, 0.1, pow(max(blurredLuma, 0.0001), 0.4545));
  float detailAmp = 1.0 + lift * 1.2 * noiseProtection;
  float detailCorrection = pow(detail, detailAmp) / detail;
  linearColor *= lumaRatio * pow(detailCorrection, 2.2);
  return vec3(
    linearToSrgb(linearColor.r), linearToSrgb(linearColor.g),
    linearToSrgb(linearColor.b)
  );
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 c = texture(uTexture, uv).rgb;

  // Base "profile" contrast first — same space/curve as the Contrast
  // slider below, mirrors render.dart's _applyBaseContrast at the top of
  // applyPostDenoisePointOps. gamma == 1.0 reduces to identity.
  c.r = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.r), 1.0 / 2.2), uBaseContrastGamma), 2.2));
  c.g = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.g), 1.0 / 2.2), uBaseContrastGamma), 2.2));
  c.b = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.b), 1.0 / 2.2), uBaseContrastGamma), 2.2));

  // RapidRAW order: filmic brightness, whites, shadows/blacks, then contrast.
  c = rapidBrightness(c, uBrightness255);
  c = rapidWhites(c, uWhitesAdd);

  c = rapidHighlights(c, uHighlightsAdd);

  // Tonal blur supplies local detail for the shadows/blacks recovery.
  // Falls off by 0.4 from each extreme (not the old hard 0.5, which fully
  // blanketed Whites/Blacks' own [0, 0.25]/[0.75, 1.0] region) with a
  // smoothstep taper instead of a linear ramp — mirrors render.dart's
  // _applyHighlightsShadows exactly.
  //
  // EXPERIMENTAL: the lift/pull is applied by scaling all 3 channels by
  // the same luma ratio (chroma-preserving), NOT by adding the flat
  // `...Add` constant to each channel independently — that flat add is
  // mathematically the atmospheric-haze/veil model (adding a constant
  // roughly equally across channels is literally how classic dehaze
  // equations model airlight), which produced a visible white/gray veil
  // on strong Shadows/Highlights/Whites/Blacks presets. Mirrors
  // render.dart's _liftLumaPreservingChroma exactly.
  // Ratio itself is clamped (not just the denominator floored) — dividing
  // by a near-zero lum (exactly the near-black pixels Shadows/Blacks are
  // meant to lift) would otherwise blow the ratio up to 50x+ for a strong
  // lift, turning a handful of the darkest pixels pure white instead of a
  // natural-looking lift. Capped lower than a first pass at 6.0 (now 2.5):
  // the whole pipeline works in 8-bit space, so near-black/near-white
  // regions only have a handful of distinct source values to begin with —
  // a high ratio can't invent intermediate values that don't exist there,
  // it just makes banding/noise already in those few values more visible.
  // Mirrors render.dart's _liftLumaPreservingChroma.
  float tonalBlurLuma = dot(
    texture(uTonalBlur, uv).rgb,
    vec3(0.2126, 0.7152, 0.0722)
  );
  c = rapidShadowsBlacks(c, uShadowsAdd, uBlacksAdd, tonalBlurLuma);

  c.r = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.r), 1.0 / 2.2), uContrastGamma), 2.2));
  c.g = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.g), 1.0 / 2.2), uContrastGamma), 2.2));
  c.b = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.b), 1.0 / 2.2), uContrastGamma), 2.2));

  // Tone curve (all 3 channels through the same LUT), then per-channel
  // color curves — matches applyToneCurve then applyColorCurves' order.
  c = clamp(c, 0.0, 1.0);
  c.r = texture(uLut, vec2(c.r, 0.5)).r;
  c.g = texture(uLut, vec2(c.g, 0.5)).r;
  c.b = texture(uLut, vec2(c.b, 0.5)).r;
  c.r = texture(uLut, vec2(c.r, 0.5)).g;
  c.g = texture(uLut, vec2(c.g, 0.5)).b;
  c.b = texture(uLut, vec2(c.b, 0.5)).a;

  // Color Mixer — color_mixer.dart's applyColorMixer, a faithful port of
  // RapidRAW's apply_hsl_panel: HSV (not HSL) in scene-linear light,
  // Gaussian-weighted per-band influence normalized per pixel, and the
  // whole effect gated by how saturated the source pixel already is.
  // Luminance (uMixer[c*3+2] for each band) included — a different code
  // path from the one previously disabled after reports of it blowing
  // out/pixelating pixels (see applyColorMixer's own doc comment). Still
  // fully unrolled by hand (no loops, no dynamic uMixer indexing — every
  // index below stays a compile-time constant): a loop-variable
  // ("dynamic") uniform-array index is exactly the kind of construct some
  // GPU shader compilers miscompile (SkSL/Impeller's translation varies
  // by backend/driver), which is what produced the blocky, garbage-
  // looking corruption previously reported when touching a Mixer/Color
  // Grading Luminance slider.
  vec3 linC = vec3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
  if (abs(linC.r - linC.g) >= 0.001 || abs(linC.g - linC.b) >= 0.001) {
    vec3 mixerHsv = rgbToHsv(linC);
    float originalHue = mixerHsv.x;
    float originalSat = mixerHsv.y;
    float originalVal = mixerHsv.z;
    float originalLuma = dot(linC, vec3(0.2126, 0.7152, 0.0722));

    float saturationMask = smoothstep(0.05, 0.20, originalSat);
    float luminanceWeight = smoothstep(0.0, 1.0, originalSat);
    if (saturationMask >= 0.001 || luminanceWeight >= 0.001) {
      float w0 = rawHslInfluence(originalHue, hslRangeCenter(0), hslRangeWidth(0));
      float w1 = rawHslInfluence(originalHue, hslRangeCenter(1), hslRangeWidth(1));
      float w2 = rawHslInfluence(originalHue, hslRangeCenter(2), hslRangeWidth(2));
      float w3 = rawHslInfluence(originalHue, hslRangeCenter(3), hslRangeWidth(3));
      float w4 = rawHslInfluence(originalHue, hslRangeCenter(4), hslRangeWidth(4));
      float w5 = rawHslInfluence(originalHue, hslRangeCenter(5), hslRangeWidth(5));
      float w6 = rawHslInfluence(originalHue, hslRangeCenter(6), hslRangeWidth(6));
      float w7 = rawHslInfluence(originalHue, hslRangeCenter(7), hslRangeWidth(7));
      float totalRaw = w0 + w1 + w2 + w3 + w4 + w5 + w6 + w7;

      float totalHueShift = 0.0, totalSatMul = 0.0, totalLumAdj = 0.0;
      float n0 = w0 / totalRaw; float hs0 = n0 * saturationMask; float lu0 = n0 * luminanceWeight;
      totalHueShift += uMixer[0] * uMixerHueStrength * hs0;
      totalSatMul += (uMixer[1] / 100.0) * hs0;
      totalLumAdj += (uMixer[2] / 100.0) * lu0;
      float n1 = w1 / totalRaw; float hs1 = n1 * saturationMask; float lu1 = n1 * luminanceWeight;
      totalHueShift += uMixer[3] * uMixerHueStrength * hs1;
      totalSatMul += (uMixer[4] / 100.0) * hs1;
      totalLumAdj += (uMixer[5] / 100.0) * lu1;
      float n2 = w2 / totalRaw; float hs2 = n2 * saturationMask; float lu2 = n2 * luminanceWeight;
      totalHueShift += uMixer[6] * uMixerHueStrength * hs2;
      totalSatMul += (uMixer[7] / 100.0) * hs2;
      totalLumAdj += (uMixer[8] / 100.0) * lu2;
      float n3 = w3 / totalRaw; float hs3 = n3 * saturationMask; float lu3 = n3 * luminanceWeight;
      totalHueShift += uMixer[9] * uMixerHueStrength * hs3;
      totalSatMul += (uMixer[10] / 100.0) * hs3;
      totalLumAdj += (uMixer[11] / 100.0) * lu3;
      float n4 = w4 / totalRaw; float hs4 = n4 * saturationMask; float lu4 = n4 * luminanceWeight;
      totalHueShift += uMixer[12] * uMixerHueStrength * hs4;
      totalSatMul += (uMixer[13] / 100.0) * hs4;
      totalLumAdj += (uMixer[14] / 100.0) * lu4;
      float n5 = w5 / totalRaw; float hs5 = n5 * saturationMask; float lu5 = n5 * luminanceWeight;
      totalHueShift += uMixer[15] * uMixerHueStrength * hs5;
      totalSatMul += (uMixer[16] / 100.0) * hs5;
      totalLumAdj += (uMixer[17] / 100.0) * lu5;
      float n6 = w6 / totalRaw; float hs6 = n6 * saturationMask; float lu6 = n6 * luminanceWeight;
      totalHueShift += uMixer[18] * uMixerHueStrength * hs6;
      totalSatMul += (uMixer[19] / 100.0) * hs6;
      totalLumAdj += (uMixer[20] / 100.0) * lu6;
      float n7 = w7 / totalRaw; float hs7 = n7 * saturationMask; float lu7 = n7 * luminanceWeight;
      totalHueShift += uMixer[21] * uMixerHueStrength * hs7;
      totalSatMul += (uMixer[22] / 100.0) * hs7;
      totalLumAdj += (uMixer[23] / 100.0) * lu7;

      if (originalSat * (1.0 + totalSatMul) < 0.0001) {
        // Matches apply_hsl_panel's own near-zero-saturation fallback:
        // collapse to gray at the (Luminance-adjusted) luma, not the HSV
        // value (the max channel) — those two aren't the same number for
        // a non-gray color.
        linC = vec3(clamp(originalLuma * (1.0 + totalLumAdj), 0.0, 1.0));
      } else {
        float newHue = mod(originalHue + totalHueShift + 360.0, 360.0);
        if (newHue < 0.0) newHue += 360.0;
        float newSat = clamp(originalSat * (1.0 + totalSatMul), 0.0, 1.0);
        vec3 shifted = hsvToRgb(newHue, newSat, originalVal);
        float newLuma = dot(shifted, vec3(0.2126, 0.7152, 0.0722));
        float targetLuma = originalLuma * (1.0 + totalLumAdj);
        if (newLuma < 0.0001) {
          linC = vec3(max(0.0, targetLuma));
        } else {
          linC = shifted * (targetLuma / newLuma);
        }
      }
    }
  }
  c = vec3(linearToSrgb(linC.r), linearToSrgb(linC.g), linearToSrgb(linC.b));

  // Color Grading — shadow/midtone/highlight partition-of-unity plus a
  // uniform-strength global tint, matching applyColorGrading exactly.
  float gLum = clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0);
  float gShadowW = clamp(1.0 - gLum * 2.0, 0.0, 1.0);
  float gHighlightW = clamp(gLum * 2.0 - 1.0, 0.0, 1.0);
  float gMidW = clamp(1.0 - gShadowW - gHighlightW, 0.0, 1.0);
  vec3 d = vec3(0.0);
  d += gShadowW * vec3(uGradeShadowTint[0], uGradeShadowTint[1], uGradeShadowTint[2]);
  d += gShadowW * uGradeShadowLum;
  d += gMidW * vec3(uGradeMidTint[0], uGradeMidTint[1], uGradeMidTint[2]);
  d += gMidW * uGradeMidLum;
  d += gHighlightW * vec3(uGradeHighlightTint[0], uGradeHighlightTint[1], uGradeHighlightTint[2]);
  d += gHighlightW * uGradeHighlightLum;
  d += vec3(uGradeGlobalTint[0], uGradeGlobalTint[1], uGradeGlobalTint[2]) + uGradeGlobalLum;
  c += d;

  fragColor = vec4(c, 1.0);
}
