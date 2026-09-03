#version 460 core
#include <flutter/runtime_effect.glsl>

// GPU port of local_contrast.dart's applyLocalContrast final combine step —
// shared by Texture (sigma=3, uNoiseAware=1) and Clarity (sigma=25,
// uProtectMidtones=1), matching the CPU side's single shared function.
// Unlike sharpen_combine.frag, there's no slider value that naturally
// zeroes the protectMidtones/noiseAware contribution to nothing (CPU
// branches on `Float32List?` being null, not on a 0 slider value), so
// this shader needs real uProtectMidtones/uNoiseAware flag uniforms
// instead — see local_contrast_gpu.dart's doc comment.

uniform vec2 uSize;
uniform float uAmount;          // amount / 100
uniform float uProtectMidtones; // 0 or 1
uniform float uNoiseAware;      // 0 or 1
// gpuResidualSqScale — uNoiseVar arrives pre-multiplied by it (see
// residual_sq.frag) and is divided back out below.
uniform float uResidualSqScale;
uniform sampler2D uSource;
uniform sampler2D uLuminance;
uniform sampler2D uBlurred;
uniform sampler2D uNoiseVar;

out vec4 fragColor;

// local_contrast.dart's "+1.0" epsilon is calibrated on the 0-255^2
// (variance) scale; rescaled to 1.0/255^2 for this shader's 0..1 working
// space, same pattern as denoise_combine.frag's kEpsilon.
const float kEpsilon = 1.0 / (255.0 * 255.0);

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec3 source = texture(uSource, uv).rgb;
  float luminance = texture(uLuminance, uv).r;
  float blurred = texture(uBlurred, uv).r;
  float noiseVar = texture(uNoiseVar, uv).r / uResidualSqScale;

  float highFreq = luminance - blurred;
  if (uProtectMidtones > 0.5) {
    float weight = clamp(1.0 - abs(luminance - 0.5) * 2.0, 0.15, 1.0);
    highFreq *= weight;
  }

  float gain = uAmount;
  if (uNoiseAware > 0.5) {
    float rSq = highFreq * highFreq;
    gain *= rSq / (rSq + noiseVar + kEpsilon);
  }

  float delta = highFreq * gain;
  fragColor = vec4(source + vec3(delta), 1.0);
}
