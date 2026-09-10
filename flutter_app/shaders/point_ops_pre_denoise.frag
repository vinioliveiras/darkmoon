#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of render.dart's applyExposureAndWhiteBalance — the two Group A
// stages that must run BEFORE baseline chroma smoothing/AI denoise (see
// applyLocalAdjustmentSteps's ordering comment).
//
// In linear light since 2026-09-10: decode sRGB, multiply by the
// white-balance gains and the exposure factor, encode back. Until then
// both multiplied the gamma-encoded value directly (with the WB gains
// pre-raised to 1/2.2 as an approximation), which is not what exposure
// or a Von Kries adaptation mean — a stop of exposure moved the linear
// luminance by more than two. The 8-bit render target still clamps at
// 1.0 on the way out, so unlike the CPU's Float32 buffer this pass keeps
// no headroom past white; that is the documented GPU/CPU difference on
// overexposed frames, unchanged here.

uniform vec2 uSize;
uniform float uRGain; // linear-light gains, whiteBalanceGains() in Dart
uniform float uBGain;
uniform float uGGain;
uniform float uRbGain; // 1.0 — kept for the uniform layout
uniform float uExposureFactor; // 2^(exposure / calExposureUnitsPerStop)
uniform sampler2D uTexture;

out vec4 fragColor;

float srgbToLinear(float c) {
  return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

float linearToSrgb(float c) {
  return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 c = texture(uTexture, uv);
  vec3 lin = vec3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
  lin *= vec3(uRGain * uRbGain, uGGain, uBGain * uRbGain) * uExposureFactor;
  lin = max(lin, vec3(0.0));
  fragColor = vec4(
    linearToSrgb(lin.r), linearToSrgb(lin.g), linearToSrgb(lin.b), c.a
  );
}
