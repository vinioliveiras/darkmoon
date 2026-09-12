#version 460 core
#include <flutter/runtime_effect.glsl>

// Negative conversion — GPU port of negative.dart's applyNegative, the
// first pass of renderImageGpu when the Negative section is on (before
// point_ops_pre_denoise.frag's Exposure/White Balance), matching where
// render.dart runs it on the CPU. Same five stages, see that file:
// density, per-channel normalisation against the measured bounds,
// weights, the pinned sigmoid, highlight desaturation, 1/2.2 out.

uniform vec2 uSize;
uniform vec3 uMin; // density at the 0.1st percentile, per channel
uniform vec3 uMax; // density at the 99.9th percentile, per channel
uniform vec3 uWeights;
uniform float uK; // NegativeParams.curve.k
uniform float uX0; // .x0
uniform float uY0; // .y0
uniform float uScale; // .scale
uniform sampler2D uTexture;

out vec4 fragColor;

float srgbToLinear(float c) {
  return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec4 src = texture(uTexture, uv);
  vec3 lin = vec3(
    srgbToLinear(src.r),
    srgbToLinear(src.g),
    srgbToLinear(src.b)
  );
  vec3 density = -log(clamp(lin, 1e-6, 1.0)) / log(10.0);
  vec3 n = max((density - uMin) / (uMax - uMin), 0.0) * uWeights;
  vec3 sigmoid = 1.0 / (1.0 + exp(-uK * (n - uX0)));
  vec3 c = clamp((sigmoid - uY0) * uScale, 0.0, 1.0);

  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  float maxCh = max(c.r, max(c.g, c.b));
  if (maxCh > 0.9) {
    float overflow = clamp((maxCh - 0.9) * 10.0, 0.0, 1.0);
    float satReduction = overflow * overflow;
    c = mix(c, vec3(luma), satReduction);
  }
  fragColor = vec4(pow(clamp(c, 0.0, 1.0), vec3(1.0 / 2.2)), src.a);
}
