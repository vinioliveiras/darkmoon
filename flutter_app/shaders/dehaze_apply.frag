#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of dehaze.dart's applyDehaze — see that function's own doc
// comment for the algorithm (a port of RapidRAW's apply_dehaze in
// shader.wgsl). uBlurred is the sigma-40 Gaussian blur of uSource
// (dehaze_gpu.dart's runGaussianBlurGpu call) — the "regional" dark-
// channel source, matching RapidRAW's structure_blur_view. Both samplers
// hold gamma-encoded values (this pipeline's universal texture
// convention); everything below runs in scene-linear light, same as
// RapidRAW's own dehaze.

uniform vec2 uSize;
uniform float uStrength; // amount/100 (dehaze.dart's `strength`)
uniform sampler2D uSource;
uniform sampler2D uBlurred;

out vec4 fragColor;

const vec3 kAtmosphericLight = vec3(0.95, 0.97, 1.0);
const vec3 kLumaWeights = vec3(0.2126, 0.7152, 0.0722);

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

vec3 srgbToLinear3(vec3 c) {
  return vec3(srgbToLinear(c.r), srgbToLinear(c.g), srgbToLinear(c.b));
}

vec3 linearToSrgb3(vec3 c) {
  return vec3(linearToSrgb(c.r), linearToSrgb(c.g), linearToSrgb(c.b));
}

float smoothstepCustom(float edge0, float edge1, float x) {
  float t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 color = srgbToLinear3(texture(uSource, uv).rgb);
  vec3 blurred = srgbToLinear3(texture(uBlurred, uv).rgb);

  vec3 result;
  if (uStrength > 0.0) {
    float pixelDark = min(color.r, min(color.g, color.b));
    float regionalDark = min(blurred.r, min(blurred.g, blurred.b));
    float pixelLuma = dot(max(color, vec3(0.0)), kLumaWeights);
    float blurredLuma = dot(max(blurred, vec3(0.0)), kLumaWeights);
    float edgeDiff = abs(sqrt(max(pixelLuma, 0.0)) - sqrt(max(blurredLuma, 0.0)));
    float haloProtection = smoothstepCustom(0.02, 0.15, edgeDiff);
    float spatialDark = mix(regionalDark, pixelDark, haloProtection);
    float safeDark = max(spatialDark - 0.02, 0.0);
    float mappedHaze = safeDark / (safeDark + 0.2);
    // Lightroom-feel calibration (item 7) — mirrors dehaze.dart's
    // _dehazeTransmissionCoeff / Floor / SatBoost / AddMix exactly.
    float t = max(1.0 - uStrength * mappedHaze * 0.55, 0.22);

    vec3 recovered = (color - kAtmosphericLight) / t + kAtmosphericLight;
    float recLuma = dot(max(recovered, vec3(0.0)), kLumaWeights);
    float shadowLift = smoothstepCustom(0.1, 0.0, recLuma) * (1.0 - t) * 0.15;
    recovered += shadowLift;

    float satBoost = (1.0 - t) * 0.32;
    float finalLuma = dot(max(recovered, vec3(0.0)), kLumaWeights);
    recovered = mix(vec3(finalLuma), recovered, 1.0 + satBoost);
    result = max(recovered, vec3(0.0));
  } else {
    float regionalDark = min(blurred.r, min(blurred.g, blurred.b));
    float safeDark = max(regionalDark - 0.02, 0.0);
    float mappedDepth = safeDark / (safeDark + 0.2);
    float depthFactor = mix(0.4, 1.0, mappedDepth);
    float hazeAmount = -uStrength;
    result = mix(color, kAtmosphericLight, hazeAmount * 0.55 * depthFactor);
  }

  fragColor = vec4(linearToSrgb3(result), 1.0);
}
