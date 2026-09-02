#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of color_profile.dart's applyColorProfile — the per-hue half
// only (hueShift/satMul/lumMul). The tone-curve half stays CPU-only: every
// profile shipped so far forces it to identity by design (see
// project_darkmoon_color_profile.md), so this pass covers everything a
// real profile actually does today. editor_screen.dart's `_runRenderJob`
// still forces CPU whenever a profile's tone curve is non-identity.
//
// Runs where render.dart's applyColorProfileStage runs it: after Clarity,
// before Dehaze (see render_gpu.dart's renderImageGpu call site).
//
// 24 hue bins, each carrying its own [hueShift, satMul, lumMul] — indexed
// by a *compile-time constant* per bin (uHueShift[0], uHueShift[1], ...)
// rather than a runtime-computed index. point_ops_post_denoise.frag's
// Color Mixer block already documents why: SkSL/Impeller has been observed
// to miscompile a uniform-array read at a loop-variable ("dynamic") index
// into visible block corruption. So instead of the CPU's nearest-two-bins
// lerp, this sums a triangular weight per bin (zero outside the bin's own
// 30°-wide support) across all 24 bins — algebraically identical to the
// CPU's `_lerpList`-style lerp between the two neighboring bins (only
// those two ever get a nonzero weight, and they sum to 1), just expressed
// as an unrolled sum of fixed-index reads instead of two dynamic ones.

uniform vec2 uSize;
// The fixed "profile" contrast S-curve (calBaseContrast) — same math as
// point_ops_post_denoise.frag's uBaseContrastGamma, moved here 2026-09-02
// to fix a real GPU/CPU order divergence: render.dart's
// applyColorProfileStage runs _applyBaseContrast (this) immediately
// before applyColorProfile (the per-hue correction below), both BEFORE
// Dehaze — but the GPU pipeline used to apply the equivalent gamma
// inside the big post-Dehaze point-ops shader instead, i.e. after
// Dehaze. At calBaseContrast's original small values this barely
// showed; at its current 80 the divergence is real. 1.0 = no-op.
uniform float uBaseContrastGamma;
uniform float uStrength; // colorProfileStrength, 0..1
uniform float uHueShift[24];
uniform float uSatMul[24];
uniform float uLumMul[24];

uniform sampler2D uTexture;

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

const float BIN_WIDTH = 15.0; // 360 / 24

float binCenter(int bin) {
  return float(bin) * BIN_WIDTH;
}

// Triangular weight, zero outside +/-BIN_WIDTH of the bin's own center,
// wrapping around the hue circle — matches the CPU's two-neighbor lerp.
float binWeight(float hue, int bin) {
  float dist = abs(hue - binCenter(bin));
  if (dist > 180.0) dist = 360.0 - dist;
  return max(0.0, 1.0 - dist / BIN_WIDTH);
}

// Endpoint-preserving S-curve (0->0, 1->1 always) — mirrors
// point_ops_post_denoise.frag's own contrastCurve exactly (kept as a
// separate copy rather than a shared include, matching how every other
// pass in this pipeline already duplicates its own small helpers).
// gamma==1.0 reduces to the identity algebraically.
float contrastCurve(float t, float gamma) {
  float x = clamp(t, 0.0, 1.0);
  if (x < 0.5) {
    return 0.5 * pow(2.0 * x, gamma);
  }
  return 1.0 - 0.5 * pow(2.0 * (1.0 - x), gamma);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 c = texture(uTexture, uv).rgb;

  // Base "profile" contrast — same slot render.dart's applyColorProfileStage
  // runs it in (right before the per-hue correction below, both before
  // Dehaze). See uBaseContrastGamma's doc comment for why this moved here.
  c.r = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.r), 1.0 / 2.2), uBaseContrastGamma), 2.2));
  c.g = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.g), 1.0 / 2.2), uBaseContrastGamma), 2.2));
  c.b = linearToSrgb(pow(contrastCurve(pow(srgbToLinear(c.b), 1.0 / 2.2), uBaseContrastGamma), 2.2));

  vec3 lin = vec3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
  if (abs(lin.r - lin.g) >= 0.001 || abs(lin.g - lin.b) >= 0.001) {
    vec3 hsv = rgbToHsv(lin);
    float hue = hsv.x;
    float sat = hsv.y;
    float val = hsv.z;
    float mask = smoothstep(0.04, 0.18, sat);
    if (mask >= 0.001) {
      float originalLuma = dot(lin, vec3(0.2126, 0.7152, 0.0722));

      float hueShiftDeg = 0.0;
      float satMulAt = 0.0;
      float lumMulAt = 0.0;
      // Fully unrolled — every uHueShift/uSatMul/uLumMul index below is a
      // compile-time constant, per the doc comment above.
      float w0 = binWeight(hue, 0); hueShiftDeg += uHueShift[0] * w0; satMulAt += (uSatMul[0] - 1.0) * w0; lumMulAt += (uLumMul[0] - 1.0) * w0;
      float w1 = binWeight(hue, 1); hueShiftDeg += uHueShift[1] * w1; satMulAt += (uSatMul[1] - 1.0) * w1; lumMulAt += (uLumMul[1] - 1.0) * w1;
      float w2 = binWeight(hue, 2); hueShiftDeg += uHueShift[2] * w2; satMulAt += (uSatMul[2] - 1.0) * w2; lumMulAt += (uLumMul[2] - 1.0) * w2;
      float w3 = binWeight(hue, 3); hueShiftDeg += uHueShift[3] * w3; satMulAt += (uSatMul[3] - 1.0) * w3; lumMulAt += (uLumMul[3] - 1.0) * w3;
      float w4 = binWeight(hue, 4); hueShiftDeg += uHueShift[4] * w4; satMulAt += (uSatMul[4] - 1.0) * w4; lumMulAt += (uLumMul[4] - 1.0) * w4;
      float w5 = binWeight(hue, 5); hueShiftDeg += uHueShift[5] * w5; satMulAt += (uSatMul[5] - 1.0) * w5; lumMulAt += (uLumMul[5] - 1.0) * w5;
      float w6 = binWeight(hue, 6); hueShiftDeg += uHueShift[6] * w6; satMulAt += (uSatMul[6] - 1.0) * w6; lumMulAt += (uLumMul[6] - 1.0) * w6;
      float w7 = binWeight(hue, 7); hueShiftDeg += uHueShift[7] * w7; satMulAt += (uSatMul[7] - 1.0) * w7; lumMulAt += (uLumMul[7] - 1.0) * w7;
      float w8 = binWeight(hue, 8); hueShiftDeg += uHueShift[8] * w8; satMulAt += (uSatMul[8] - 1.0) * w8; lumMulAt += (uLumMul[8] - 1.0) * w8;
      float w9 = binWeight(hue, 9); hueShiftDeg += uHueShift[9] * w9; satMulAt += (uSatMul[9] - 1.0) * w9; lumMulAt += (uLumMul[9] - 1.0) * w9;
      float w10 = binWeight(hue, 10); hueShiftDeg += uHueShift[10] * w10; satMulAt += (uSatMul[10] - 1.0) * w10; lumMulAt += (uLumMul[10] - 1.0) * w10;
      float w11 = binWeight(hue, 11); hueShiftDeg += uHueShift[11] * w11; satMulAt += (uSatMul[11] - 1.0) * w11; lumMulAt += (uLumMul[11] - 1.0) * w11;
      float w12 = binWeight(hue, 12); hueShiftDeg += uHueShift[12] * w12; satMulAt += (uSatMul[12] - 1.0) * w12; lumMulAt += (uLumMul[12] - 1.0) * w12;
      float w13 = binWeight(hue, 13); hueShiftDeg += uHueShift[13] * w13; satMulAt += (uSatMul[13] - 1.0) * w13; lumMulAt += (uLumMul[13] - 1.0) * w13;
      float w14 = binWeight(hue, 14); hueShiftDeg += uHueShift[14] * w14; satMulAt += (uSatMul[14] - 1.0) * w14; lumMulAt += (uLumMul[14] - 1.0) * w14;
      float w15 = binWeight(hue, 15); hueShiftDeg += uHueShift[15] * w15; satMulAt += (uSatMul[15] - 1.0) * w15; lumMulAt += (uLumMul[15] - 1.0) * w15;
      float w16 = binWeight(hue, 16); hueShiftDeg += uHueShift[16] * w16; satMulAt += (uSatMul[16] - 1.0) * w16; lumMulAt += (uLumMul[16] - 1.0) * w16;
      float w17 = binWeight(hue, 17); hueShiftDeg += uHueShift[17] * w17; satMulAt += (uSatMul[17] - 1.0) * w17; lumMulAt += (uLumMul[17] - 1.0) * w17;
      float w18 = binWeight(hue, 18); hueShiftDeg += uHueShift[18] * w18; satMulAt += (uSatMul[18] - 1.0) * w18; lumMulAt += (uLumMul[18] - 1.0) * w18;
      float w19 = binWeight(hue, 19); hueShiftDeg += uHueShift[19] * w19; satMulAt += (uSatMul[19] - 1.0) * w19; lumMulAt += (uLumMul[19] - 1.0) * w19;
      float w20 = binWeight(hue, 20); hueShiftDeg += uHueShift[20] * w20; satMulAt += (uSatMul[20] - 1.0) * w20; lumMulAt += (uLumMul[20] - 1.0) * w20;
      float w21 = binWeight(hue, 21); hueShiftDeg += uHueShift[21] * w21; satMulAt += (uSatMul[21] - 1.0) * w21; lumMulAt += (uLumMul[21] - 1.0) * w21;
      float w22 = binWeight(hue, 22); hueShiftDeg += uHueShift[22] * w22; satMulAt += (uSatMul[22] - 1.0) * w22; lumMulAt += (uLumMul[22] - 1.0) * w22;
      float w23 = binWeight(hue, 23); hueShiftDeg += uHueShift[23] * w23; satMulAt += (uSatMul[23] - 1.0) * w23; lumMulAt += (uLumMul[23] - 1.0) * w23;

      hueShiftDeg *= uStrength * mask;
      float satMul = 1.0 + satMulAt * uStrength * mask;
      float lumMul = 1.0 + lumMulAt * uStrength * mask;

      float newHue = mod(hue + hueShiftDeg, 360.0);
      if (newHue < 0.0) newHue += 360.0;
      float newSat = clamp(sat * satMul, 0.0, 1.0);
      vec3 shifted = hsvToRgb(newHue, newSat, val);
      float shiftedLuma = dot(shifted, vec3(0.2126, 0.7152, 0.0722));
      float targetLuma = originalLuma * lumMul;
      if (shiftedLuma < 0.0001) {
        lin = vec3(max(0.0, targetLuma));
      } else {
        lin = shifted * (targetLuma / shiftedLuma);
      }
    }
  }

  c = vec3(linearToSrgb(lin.r), linearToSrgb(lin.g), linearToSrgb(lin.b));
  fragColor = vec4(c, 1.0);
}
