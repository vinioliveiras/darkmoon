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

// Brightness/contrast — render.dart's _applyBrightnessContrast.
uniform float uBrightness255; // brightness param, still 0..100-ish scale
uniform float uContrastFactor; // 1 + contrast/100

// Highlights/shadows — _applyHighlightsShadows. Precomputed as
// (param/100)*80/255 on the CPU side so the shader just multiplies by a
// per-pixel weight.
uniform float uShadowsAdd;
uniform float uHighlightsAdd;

// Whites/blacks — _applyWhitesBlacks. Precomputed as (param/100)*100/255.
uniform float uWhitesAdd;
uniform float uBlacksAdd;

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

out vec4 fragColor;

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

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 c = texture(uTexture, uv).rgb;

  // Brightness/contrast.
  c = (c - 0.5) * uContrastFactor + 0.5 + uBrightness255 / 255.0;

  // Highlights/shadows + whites/blacks share one Rec.709 luminance sample
  // (matches render.dart computing it once per stage from the
  // *pre*-stage value, not recomputed after each add).
  float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
  float shadowW = clamp(1.0 - lum * 2.0, 0.0, 1.0);
  float highlightW = clamp((lum - 0.5) * 2.0, 0.0, 1.0);
  c += shadowW * uShadowsAdd + highlightW * uHighlightsAdd;

  float lum2 = dot(c, vec3(0.2126, 0.7152, 0.0722));
  float whitesW = clamp((lum2 - 0.75) * 4.0, 0.0, 1.0);
  float blacksW = clamp(1.0 - lum2 * 4.0, 0.0, 1.0);
  c += whitesW * uWhitesAdd + blacksW * uBlacksAdd;

  // Tone curve (all 3 channels through the same LUT), then per-channel
  // color curves — matches applyToneCurve then applyColorCurves' order.
  c = clamp(c, 0.0, 1.0);
  c.r = texture(uLut, vec2(c.r, 0.5)).r;
  c.g = texture(uLut, vec2(c.g, 0.5)).r;
  c.b = texture(uLut, vec2(c.b, 0.5)).r;
  c.r = texture(uLut, vec2(c.r, 0.5)).g;
  c.g = texture(uLut, vec2(c.g, 0.5)).b;
  c.b = texture(uLut, vec2(c.b, 0.5)).a;

  // Color Mixer.
  vec3 hsl = rgbToHsl(clamp(c, 0.0, 1.0));
  float hueShift = 0.0, satShift = 0.0, lumShift = 0.0;
  for (int band = 0; band < 8; band++) {
    float w = bandWeight(hsl.x, mixerCenterHue(band));
    if (w <= 0.0) continue;
    hueShift += w * uMixer[band * 3];
    satShift += w * uMixer[band * 3 + 1];
    lumShift += w * uMixer[band * 3 + 2];
  }
  float newHue = mod(hsl.x + hueShift * 0.3, 360.0);
  if (newHue < 0.0) newHue += 360.0;
  float newSat = clamp(hsl.y * (1.0 + satShift / 100.0), 0.0, 1.0);
  float newLight = clamp(hsl.z + lumShift / 100.0 * 0.5, 0.0, 1.0);
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
