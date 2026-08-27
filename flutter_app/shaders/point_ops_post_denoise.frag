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

// Highlights/shadows — _applyHighlightsShadows. Precomputed as
// (param/100)*80/255 on the CPU side so the shader just multiplies by a
// per-pixel weight.
uniform float uShadowsAdd; // shadows param normalized from -100..100
uniform float uHighlightsAdd;

// Whites/blacks — _applyWhitesBlacks. Precomputed as (param/100)*100/255.
uniform float uWhitesAdd; // whites param normalized from -100..100
uniform float uBlacksAdd; // blacks param normalized from -100..100

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
// (array initializers) — matches color_mixer.dart's _channelCenterHues via
// an if-chain instead of an array literal.
float mixerCenterHue(int band) {
  if (band == 0) return 0.0;
  if (band == 1) return 30.0;
  if (band == 2) return 60.0;
  if (band == 3) return 120.0;
  if (band == 4) return 180.0;
  if (band == 5) return 240.0;
  if (band == 6) return 275.0;
  return 315.0; // band == 7
}

// Mirrors color_mixer.dart's _bandWeight exactly.
float bandWeight(float hue, float center) {
  float diff = abs(hue - center);
  if (diff > 180.0) diff = 360.0 - diff;
  const float halfWidth = 45.0;
  return diff >= halfWidth ? 0.0 : 1.0 - diff / halfWidth;
}

// Mirrors hsl.dart's rgbToHsl (h in degrees, s/l in 0..1).
vec3 rgbToHsl(vec3 c) {
  float maxC = max(c.r, max(c.g, c.b));
  float minC = min(c.r, min(c.g, c.b));
  float light = (maxC + minC) * 0.5;
  if (maxC == minC) return vec3(0.0, 0.0, light);
  float d = maxC - minC;
  float sat = light > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC);
  float hue;
  if (maxC == c.r) {
    hue = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
  } else if (maxC == c.g) {
    hue = (c.b - c.r) / d + 2.0;
  } else {
    hue = (c.r - c.g) / d + 4.0;
  }
  hue *= 60.0;
  return vec3(hue, sat, light);
}

// Mirrors hsl.dart's _hueToRgbComponent + hslToRgb.
float hueToRgbComponent(float p, float q, float t) {
  float tt = t;
  if (tt < 0.0) tt += 1.0;
  if (tt > 1.0) tt -= 1.0;
  if (tt < 1.0 / 6.0) return p + (q - p) * 6.0 * tt;
  if (tt < 0.5) return q;
  if (tt < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - tt) * 6.0;
  return p;
}

vec3 hslToRgb(float h, float s, float l) {
  if (s == 0.0) return vec3(l, l, l);
  float q = l < 0.5 ? l * (1.0 + s) : l + s - l * s;
  float p = 2.0 * l - q;
  float hk = h / 360.0;
  return vec3(
    hueToRgbComponent(p, q, hk + 1.0 / 3.0),
    hueToRgbComponent(p, q, hk),
    hueToRgbComponent(p, q, hk - 1.0 / 3.0)
  );
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

float rapidWhiteMask(float luma) {
  float whiteInput = tanh(max(luma, 0.0001) * 1.5);
  return smoothstep(0.5, 0.98, whiteInput);
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
  float level = 1.0 - amount * 0.25;
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
  float blackLift = blacks * t * pow(max(1.0 - t, 0.0), 12.0);
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

  // Color Mixer — unrolled by hand rather than a runtime for-loop indexing
  // uMixer[band * 3]: that loop-variable ("dynamic") uniform-array index
  // is exactly the kind of construct some GPU shader compilers miscompile
  // (SkSL/Impeller's translation varies by backend/driver), which is what
  // produced the blocky, garbage-looking corruption reported when
  // touching a Mixer/Color Grading Luminance slider — every index below
  // is now a compile-time constant.
  // Luminance (uMixer[c*3+2] for each band) intentionally not applied —
  // disabled per-channel in the UI too (see editor_screen.dart's Mixer/
  // HSL panel) after repeated reports of it blowing out/pixelating
  // pixels, even after fixing the uniform-array-indexed-by-loop-variable
  // bug that caused the blocky corruption. Mirrors color_mixer.dart's
  // applyColorMixer exactly.
  vec3 hsl = rgbToHsl(clamp(c, 0.0, 1.0));
  float hueShift = 0.0, satShift = 0.0;
  float w0 = bandWeight(hsl.x, mixerCenterHue(0));
  hueShift += w0 * uMixer[0];
  satShift += w0 * uMixer[1];
  float w1 = bandWeight(hsl.x, mixerCenterHue(1));
  hueShift += w1 * uMixer[3];
  satShift += w1 * uMixer[4];
  float w2 = bandWeight(hsl.x, mixerCenterHue(2));
  hueShift += w2 * uMixer[6];
  satShift += w2 * uMixer[7];
  float w3 = bandWeight(hsl.x, mixerCenterHue(3));
  hueShift += w3 * uMixer[9];
  satShift += w3 * uMixer[10];
  float w4 = bandWeight(hsl.x, mixerCenterHue(4));
  hueShift += w4 * uMixer[12];
  satShift += w4 * uMixer[13];
  float w5 = bandWeight(hsl.x, mixerCenterHue(5));
  hueShift += w5 * uMixer[15];
  satShift += w5 * uMixer[16];
  float w6 = bandWeight(hsl.x, mixerCenterHue(6));
  hueShift += w6 * uMixer[18];
  satShift += w6 * uMixer[19];
  float w7 = bandWeight(hsl.x, mixerCenterHue(7));
  hueShift += w7 * uMixer[21];
  satShift += w7 * uMixer[22];
  float newHue = mod(hsl.x + hueShift * 0.3, 360.0);
  if (newHue < 0.0) newHue += 360.0;
  float newSat = clamp(hsl.y * (1.0 + satShift / 100.0), 0.0, 1.0);
  float newLight = hsl.z;
  c = hslToRgb(newHue, newSat, newLight);

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
