#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of render.dart's white balance + exposure — the two Group A
// stages that must run BEFORE baseline chroma smoothing/AI denoise (see
// applyLocalAdjustmentSteps's ordering comment). Ported 1:1 from
// _applyWhiteBalance/_applyExposure in render.dart; working space here is
// 0..1 (GPU texture-normalized), matching CPU's 0..255 math scaled down.

uniform vec2 uSize;
uniform float uRGain; // 1 + tempGain
uniform float uBGain; // 1 - tempGain
uniform float uGGain; // 1 - tintShift
uniform float uRbGain; // 1 + tintShift * 0.5
uniform float uExposureFactor; // 2^(exposure/100*3)
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 c = texture(uTexture, uv);
  float r = c.r * uRGain * uRbGain;
  float g = c.g * uGGain;
  float b = c.b * uBGain * uRbGain;
  r *= uExposureFactor;
  g *= uExposureFactor;
  b *= uExposureFactor;
  fragColor = vec4(r, g, b, c.a);
}
